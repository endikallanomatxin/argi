const std = @import("std");
const diagnostics = @import("../1_base/diagnostic.zig");
const sg = @import("semantic_graph.zig");
const facts = @import("safety_facts.zig");
const place = @import("place.zig");
const value_state = @import("value_state.zig");

/// Infers temporal effects from semantized bodies. Summaries are deliberately
/// compiler-owned: ordinary functions have no source contract to maintain.
pub const SafetyChecker = struct {
    allocator: *const std.mem.Allocator,
    diagnostics: *diagnostics.Diagnostics,
    summaries: std.AutoHashMap(*const sg.FunctionDeclaration, facts.FunctionSummary),

    pub fn init(allocator: *const std.mem.Allocator, diags: *diagnostics.Diagnostics) SafetyChecker {
        return .{
            .allocator = allocator,
            .diagnostics = diags,
            .summaries = std.AutoHashMap(*const sg.FunctionDeclaration, facts.FunctionSummary).init(allocator.*),
        };
    }

    pub fn deinit(self: *SafetyChecker) void {
        self.summaries.deinit();
    }

    pub fn analyze(self: *SafetyChecker, nodes: []const *sg.SGNode) !void {
        const diagnostic_count = self.diagnostics.list.items.len;
        var functions = std.array_list.Managed(*const sg.FunctionDeclaration).init(self.allocator.*);
        defer functions.deinit();
        for (nodes) |node| switch (node.content) {
            .function_declaration => |function| try functions.append(function),
            .test_declaration => |test_decl| try functions.append(test_decl.function),
            else => {},
        };

        for (functions.items) |function| try self.ensureEmptySummary(function);
        const limit = @max(functions.items.len + 1, 1);
        for (0..limit) |_| {
            var changed = false;
            for (functions.items) |function| changed = (try self.infer(function)) or changed;
            if (!changed) break;
        }
        for (functions.items) |function| try self.validateFunction(function);
        if (self.diagnostics.list.items.len != diagnostic_count) return error.Reported;
    }

    const FunctionState = struct {
        tracker: facts.Tracker,
        places: std.array_list.Managed(facts.PlaceFacts),
        storage_roots: std.AutoHashMap(*const sg.BindingDeclaration, facts.RootId),
        reachable: bool = true,
        ownership_conflict_reported: bool = false,

        fn init(allocator: std.mem.Allocator) FunctionState {
            return .{
                .tracker = facts.Tracker.init(allocator),
                .places = std.array_list.Managed(facts.PlaceFacts).init(allocator),
                .storage_roots = std.AutoHashMap(*const sg.BindingDeclaration, facts.RootId).init(allocator),
            };
        }

        fn deinit(self: *FunctionState) void {
            self.tracker.deinit();
            self.places.deinit();
            self.storage_roots.deinit();
        }

        fn clone(self: *const FunctionState, allocator: std.mem.Allocator) !FunctionState {
            var result = FunctionState.init(allocator);
            try result.tracker.roots.appendSlice(self.tracker.roots.items);
            try result.places.appendSlice(self.places.items);
            var roots = self.storage_roots.iterator();
            while (roots.next()) |entry| try result.storage_roots.put(entry.key_ptr.*, entry.value_ptr.*);
            result.reachable = self.reachable;
            result.ownership_conflict_reported = self.ownership_conflict_reported;
            return result;
        }
    };

    fn validateFunction(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !void {
        const body = function.body orelse return;
        if (function.safety_primitive != .none) return;
        if (std.mem.indexOf(u8, function.location.file, "core/") != null) return;
        var state = FunctionState.init(self.allocator.*);
        defer state.deinit();
        // Argi pointer parameters may alias. Until a call-site proof can
        // partition them, one shared root conservatively represents any
        // temporal invalidation observable through compatible inputs.
        var pointer_input_root: ?facts.RootId = null;
        for (function.input_bindings) |binding| {
            if (binding.ty == .pointer_type) {
                const root = pointer_input_root orelse blk: {
                    const established = try state.tracker.establish(.fresh);
                    pointer_input_root = established;
                    break :blk established;
                };
                try self.setPlace(&state, .{ .root = binding }, .initialized, .{ .dependencies = try self.oneDependency(root) });
            } else {
                try self.setPlace(&state, .{ .root = binding }, .initialized, .{});
            }
        }
        try self.validateBlock(function, body, &state);
        if (state.reachable) try self.rejectEscapingLocalRoots(function, &state);
    }

    fn validateBlock(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        state: *FunctionState,
    ) anyerror!void {
        for (block.nodes) |node| {
            switch (node.content) {
                .binding_declaration => |binding| {
                    const value = if (binding.initialization) |initialization|
                        try self.evaluate(function, initialization, state)
                    else
                        facts.ValueFacts{};
                    try self.setPlace(state, .{ .root = binding }, .initialized, value);
                },
                .binding_assignment => |assignment| {
                    const value = try self.evaluate(function, assignment.value, state);
                    try self.setPlace(state, .{ .root = assignment.sym_id }, .initialized, value);
                },
                .auto_deinit_binding => |cleanup| {
                    const storage = place.Place{ .root = cleanup.binding };
                    if (self.getPlace(state, storage)) |owned_value|
                        for (owned_value.value.owned_roots) |root| state.tracker.end(root);
                    try self.setPlace(state, storage, .deinitialized, .{});
                },
                .struct_field_store => |store| {
                    _ = try self.evaluate(function, store.struct_ptr, state);
                    const target = try self.projectedPlace(try self.resolvePlace(store.struct_ptr, state) orelse continue, .{ .field = store.field_index });
                    try self.setPlace(state, target, .initialized, try self.evaluate(function, store.value, state));
                },
                .array_store => |store| {
                    _ = try self.evaluate(function, store.array_ptr, state);
                    const projection: place.Projection = if (staticIndex(store.index)) |index|
                        .{ .static_index = index }
                    else
                        .dynamic_index;
                    const target = try self.projectedPlace(try self.resolvePlace(store.array_ptr, state) orelse continue, projection);
                    try self.setPlace(state, target, .initialized, try self.evaluate(function, store.value, state));
                },
                .pointer_assignment => |assignment| {
                    const pointer = try self.evaluate(function, assignment.pointer, state);
                    if (pointer.referenced_place) |target|
                        try self.setPlace(state, target, .initialized, try self.evaluate(function, assignment.value, state));
                },
                .function_call, .dereference, .explicit_cast, .struct_field_access, .array_index => _ = try self.evaluate(function, node, state),
                .if_statement => |statement| {
                    _ = try self.evaluate(function, statement.condition, state);
                    var then_state = try state.clone(self.allocator.*);
                    defer then_state.deinit();
                    try self.validateBlock(function, statement.then_block, &then_state);
                    var else_state = try state.clone(self.allocator.*);
                    defer else_state.deinit();
                    if (statement.else_block) |else_block| try self.validateBlock(function, else_block, &else_state);
                    try self.joinStates(function, state, &then_state, &else_state);
                },
                .while_statement => |statement| {
                    _ = try self.evaluate(function, statement.condition, state);
                    try self.validateLoop(function, statement.body, state, null);
                },
                .for_statement => |statement| {
                    if (statement.init) |initialization| _ = try self.evaluate(function, initialization, state);
                    _ = try self.evaluate(function, statement.condition, state);
                    try self.validateLoop(function, statement.body, state, statement.increment);
                },
                .return_statement => |statement| {
                    if (statement.expression) |expression| {
                        const output = try self.evaluate(function, expression, state);
                        if (expression.sem_type) |ty| if (typeContainsPointer(ty))
                            try self.rejectEscapingValue(function, output, state);
                    }
                    try self.rejectEscapingLocalRoots(function, state);
                    state.reachable = false;
                },
                .switch_statement => |statement| {
                    _ = try self.evaluate(function, statement.expression, state);
                    var joined: ?FunctionState = null;
                    defer if (joined) |*joined_state| joined_state.deinit();
                    for (statement.cases) |case| {
                        var branch = try state.clone(self.allocator.*);
                        defer branch.deinit();
                        try self.validateBlock(function, case.body, &branch);
                        if (joined) |*joined_state| {
                            var combined = try state.clone(self.allocator.*);
                            try self.joinStates(function, &combined, joined_state, &branch);
                            joined_state.deinit();
                            joined_state.* = combined;
                        } else joined = try branch.clone(self.allocator.*);
                    }
                    if (statement.default_case) |default_case| {
                        var branch = try state.clone(self.allocator.*);
                        defer branch.deinit();
                        try self.validateBlock(function, default_case, &branch);
                        if (joined) |*joined_state| {
                            var combined = try state.clone(self.allocator.*);
                            try self.joinStates(function, &combined, joined_state, &branch);
                            joined_state.deinit();
                            joined_state.* = combined;
                        } else joined = try branch.clone(self.allocator.*);
                    } else if (joined) |*joined_state| {
                        var combined = try state.clone(self.allocator.*);
                        try self.joinStates(function, &combined, joined_state, state);
                        joined_state.deinit();
                        joined_state.* = combined;
                    }
                    if (joined) |*joined_state| try self.copyState(state, joined_state);
                },
                else => {},
            }
            try self.validateUniqueOwnership(function, state);
            if (!state.reachable) return;
        }
    }

    fn evaluate(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        return switch (node.content) {
            .binding_use => |binding| blk: {
                const storage = place.Place{ .root = binding };
                if (self.getPlace(state, storage)) |place_facts| {
                    try self.requireInitialized(function, place_facts);
                    break :blk place_facts.value;
                }
                break :blk .{};
            },
            .move_value => |value| blk: {
                const result = try self.evaluate(function, value, state);
                if (try self.resolvePlace(value, state)) |source|
                    try self.setPlace(state, source, .moved, .{});
                break :blk result;
            },
            .address_of => |value| blk: {
                const target = try self.resolvePlace(value, state);
                break :blk .{
                    .dependencies = try self.oneDependency(try self.storageRoot(value, state)),
                    .referenced_place = target,
                };
            },
            .dereference => |dereference| blk: {
                const pointer = try self.evaluate(function, dereference.pointer, state);
                if (!state.tracker.dependenciesAreAlive(pointer)) {
                    try self.diagnostics.add(function.location, .semantic, "reference depends on a root that has ended", .{});
                }
                if (pointer.referenced_place) |target| {
                    if (self.getPlace(state, target)) |place_facts| {
                        try self.requireInitialized(function, place_facts);
                        break :blk place_facts.value;
                    }
                }
                break :blk facts.ValueFacts{};
            },
            .struct_value_literal => |literal| try self.aggregate(function, literal.fields, state),
            .struct_field_access => |access| blk: {
                if (try self.resolvePlace(node, state)) |storage| {
                    if (self.getPlace(state, storage)) |place_facts| {
                        try self.requireInitialized(function, place_facts);
                        break :blk place_facts.value;
                    }
                }
                const aggregate_value = try self.evaluate(function, access.struct_value, state);
                for (aggregate_value.fields) |field| {
                    if (field.index == access.field_index) break :blk field.value.*;
                }
                break :blk aggregate_value;
            },
            .array_index => |index| blk: {
                _ = try self.evaluate(function, index.array_ptr, state);
                if (try self.resolvePlace(node, state)) |storage| {
                    if (self.getPlace(state, storage)) |place_facts| {
                        try self.requireInitialized(function, place_facts);
                        break :blk place_facts.value;
                    }
                }
                break :blk .{};
            },
            .explicit_cast => |cast| blk: {
                const value = try self.evaluate(function, cast.value, state);
                const target_is_integer = cast.target_type == .builtin and cast.target_type.builtin == .UIntNative;
                const target_is_reference = cast.target_type == .pointer_type;
                const target_is_raw_any = target_is_reference and
                    cast.target_type.pointer_type.child.* == .builtin and
                    cast.target_type.pointer_type.child.*.builtin == .Any;
                const source_is_reference = cast.value.sem_type != null and cast.value.sem_type.? == .pointer_type;
                const source_is_integer = cast.value.sem_type != null and
                    cast.value.sem_type.? == .builtin and
                    switch (cast.value.sem_type.?.builtin) {
                        .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64 => true,
                        else => false,
                    };
                if (target_is_integer and (source_is_reference or value.foreign_storage))
                    break :blk facts.ValueFacts{
                        .integer_address = true,
                        .foreign_storage = value.foreign_storage or value.dependencies.len == 0,
                    };
                if (target_is_reference and !target_is_raw_any and
                    (source_is_integer or value.integer_address) and !value.foreign_storage)
                {
                    try self.diagnostics.add(function.location, .semantic, "an integer address cannot establish a safe reference; use RawPointer and explicit root establishment", .{});
                }
                break :blk .{};
            },
            .function_call => |call| try self.evaluateCall(function, call, state),
            .virtualize => |virtualize| try self.evaluate(function, virtualize.value, state),
            .virtual_call => |call| try self.evaluate(function, call.input, state),
            .binary_operation => |operation| blk: {
                _ = try self.evaluate(function, operation.left, state);
                _ = try self.evaluate(function, operation.right, state);
                break :blk .{};
            },
            .comparison => |comparison| blk: {
                _ = try self.evaluate(function, comparison.left, state);
                _ = try self.evaluate(function, comparison.right, state);
                break :blk .{};
            },
            .logical_operation => |operation| blk: {
                _ = try self.evaluate(function, operation.left, state);
                _ = try self.evaluate(function, operation.right, state);
                break :blk .{};
            },
            else => .{},
        };
    }

    fn evaluateCall(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        call: *const sg.FunctionCall,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        var arguments: []const sg.StructValueLiteralField = &.{};
        if (call.input.content == .struct_value_literal) arguments = call.input.content.struct_value_literal.fields;
        const argument_values = try self.allocator.alloc(facts.ValueFacts, arguments.len);
        for (arguments, 0..) |argument, index| argument_values[index] = try self.evaluate(function, argument.value, state);
        if (call.callee.safety_primitive == .establish_fresh_reference or
            call.callee.safety_primitive == .establish_inherited_reference or
            call.callee.safety_primitive == .establish_allocation)
        {
            const has_foreign_storage = argument_values.len != 0 and argument_values[0].foreign_storage;
            if (!has_foreign_storage and call.callee.safety_primitive != .establish_allocation)
                try self.diagnostics.add(function.location, .semantic, "raw-to-safe reference establishment is restricted to compiler-owned storage boundaries", .{});
            if (call.callee.safety_primitive == .establish_allocation)
                try self.diagnostics.add(function.location, .semantic, "allocation root establishment is restricted to compiler-owned storage boundaries", .{});
        }
        if (std.mem.eql(u8, call.callee.name, "deallocate") and arguments.len > 1) {
            const data = argument_values[1];
            for (data.dependencies) |dependency| state.tracker.end(dependency.root);
            return .{};
        }
        if (call.callee.body == null and call.callee.output.fields.len == 1 and
            call.callee.output.fields[0].ty == .pointer_type)
            return .{ .foreign_storage = true };
        const summary = self.summaries.get(call.callee) orelse return .{};
        for (summary.ends_input_roots) |index| {
            if (index >= arguments.len) continue;
            const target = argument_values[index].referenced_place orelse
                try self.resolvePlace(arguments[index].value, state);
            if (target) |storage| {
                if (self.getPlace(state, storage)) |place_facts| {
                    for (place_facts.value.owned_roots) |owned_root| state.tracker.end(owned_root);
                    var remaining = place_facts.value;
                    remaining.owned_roots = &.{};
                    try self.setPlace(state, storage, .initialized, remaining);
                }
            }
        }
        for (summary.deinitializes_inputs) |index| {
            if (index >= arguments.len) continue;
            const target = argument_values[index].referenced_place orelse
                try self.resolvePlace(arguments[index].value, state);
            if (target) |storage|
                try self.setPlace(state, storage, .deinitialized, .{});
        }
        if (summary.outputs.len != 1) return .{};
        return self.instantiateOutput(summary.outputs[0], argument_values, state);
    }

    fn instantiateOutput(
        self: *SafetyChecker,
        effect: facts.OutputEffect,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !facts.ValueFacts {
        var fresh_roots = std.AutoHashMap(facts.FreshRootSource, facts.RootId).init(self.allocator.*);
        defer fresh_roots.deinit();
        return self.instantiateOutputWithFresh(effect, arguments, state, &fresh_roots);
    }

    fn instantiateOutputWithFresh(
        self: *SafetyChecker,
        effect: facts.OutputEffect,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
        fresh_roots: *std.AutoHashMap(facts.FreshRootSource, facts.RootId),
    ) !facts.ValueFacts {
        var result: facts.ValueFacts = .{};
        var dependencies = std.array_list.Managed(facts.ReferenceDependency).init(self.allocator.*);
        for (effect.fresh_dependencies) |source| {
            const root = try self.instantiateFreshRoot(source, state, fresh_roots);
            try appendDependency(&dependencies, .{ .root = root });
        }
        result.dependencies = try dependencies.toOwnedSlice();
        var owned_roots = std.array_list.Managed(facts.RootId).init(self.allocator.*);
        for (effect.fresh_owned_roots) |source| {
            const root = try self.instantiateFreshRoot(source, state, fresh_roots);
            try appendOwnedRoot(&owned_roots, root);
        }
        result.owned_roots = try owned_roots.toOwnedSlice();
        for (effect.input_dependencies) |dependency| {
            if (dependency.input_index >= arguments.len) continue;
            var input = arguments[dependency.input_index];
            input = projectValueFacts(input, dependency.projections);
            if (!dependency.transfers_ownership) input.owned_roots = &.{};
            result = try self.mergeValueFacts(result, input);
        }
        if (effect.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.FieldFacts, effect.fields.len);
            for (effect.fields, 0..) |field, index| {
                const value = try self.allocator.create(facts.ValueFacts);
                value.* = try self.instantiateOutputWithFresh(field.value.*, arguments, state, fresh_roots);
                fields[index] = .{ .index = field.index, .value = value };
                result = try self.mergeValueFacts(result, value.*);
            }
            result.fields = fields;
        }
        result.integer_address = effect.integer_address;
        result.foreign_storage = result.foreign_storage or effect.foreign_storage;
        return result;
    }

    fn instantiateFreshRoot(
        self: *SafetyChecker,
        source: facts.FreshRootSource,
        state: *FunctionState,
        fresh_roots: *std.AutoHashMap(facts.FreshRootSource, facts.RootId),
    ) !facts.RootId {
        _ = self;
        if (fresh_roots.get(source)) |root| return root;
        const root = try state.tracker.establish(.fresh);
        try fresh_roots.put(source, root);
        return root;
    }

    fn mergeValueFacts(self: *SafetyChecker, left: facts.ValueFacts, right: facts.ValueFacts) !facts.ValueFacts {
        var dependencies = std.array_list.Managed(facts.ReferenceDependency).init(self.allocator.*);
        for (left.dependencies) |dependency| try appendDependency(&dependencies, dependency);
        for (right.dependencies) |dependency| try appendDependency(&dependencies, dependency);
        var owned_roots = std.array_list.Managed(facts.RootId).init(self.allocator.*);
        for (left.owned_roots) |owned_root| try appendOwnedRoot(&owned_roots, owned_root);
        for (right.owned_roots) |owned_root| try appendOwnedRoot(&owned_roots, owned_root);
        var fields = std.array_list.Managed(facts.FieldFacts).init(self.allocator.*);
        for (left.fields) |left_field| {
            var merged = left_field.value.*;
            for (right.fields) |right_field| if (right_field.index == left_field.index) {
                merged = try self.mergeValueFacts(merged, right_field.value.*);
                break;
            };
            const stored = try self.allocator.create(facts.ValueFacts);
            stored.* = merged;
            try fields.append(.{ .index = left_field.index, .value = stored });
        }
        for (right.fields) |right_field| {
            var found = false;
            for (left.fields) |left_field| if (left_field.index == right_field.index) {
                found = true;
                break;
            };
            if (!found) try fields.append(right_field);
        }
        return .{
            .dependencies = try dependencies.toOwnedSlice(),
            .owned_roots = try owned_roots.toOwnedSlice(),
            .fields = try fields.toOwnedSlice(),
            .integer_address = left.integer_address or right.integer_address,
            .foreign_storage = left.foreign_storage or right.foreign_storage,
            .referenced_place = if (left.referenced_place != null and right.referenced_place != null and left.referenced_place.?.eql(right.referenced_place.?))
                left.referenced_place
            else
                null,
        };
    }

    /// Dependencies and cleanup obligations both widen at a join. A place may
    /// own a root on only some incoming paths; initializedness records that the
    /// value cannot be used unconditionally, while auto-deinit consumes the
    /// remaining per-path obligation through its runtime drop flag.
    fn joinValueFacts(self: *SafetyChecker, left: facts.ValueFacts, right: facts.ValueFacts) !facts.ValueFacts {
        var result = try self.mergeValueFacts(left, right);

        const fields = try self.allocator.alloc(facts.FieldFacts, result.fields.len);
        for (result.fields, 0..) |field, index| {
            const stored = try self.allocator.create(facts.ValueFacts);
            const left_field = findField(left.fields, field.index);
            const right_field = findField(right.fields, field.index);
            if (left_field != null and right_field != null) {
                stored.* = try self.joinValueFacts(left_field.?.value.*, right_field.?.value.*);
            } else {
                stored.* = field.value.*;
            }
            fields[index] = .{ .index = field.index, .value = stored };
        }
        result.fields = fields;
        return result;
    }

    fn copyState(self: *SafetyChecker, destination: *FunctionState, source: *const FunctionState) !void {
        const replacement = try source.clone(self.allocator.*);
        destination.deinit();
        destination.* = replacement;
    }

    fn joinStates(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        destination: *FunctionState,
        left: *const FunctionState,
        right: *const FunctionState,
    ) !void {
        _ = function;
        if (!left.reachable) return self.copyState(destination, right);
        if (!right.reachable) return self.copyState(destination, left);
        var joined = FunctionState.init(self.allocator.*);
        errdefer joined.deinit();
        const root_count = @max(left.tracker.roots.items.len, right.tracker.roots.items.len);
        for (0..root_count) |index| {
            const id: facts.RootId = @enumFromInt(index);
            const left_state = if (index < left.tracker.roots.items.len) left.tracker.roots.items[index].state else .dead;
            const right_state = if (index < right.tracker.roots.items.len) right.tracker.roots.items[index].state else .dead;
            const root_state: @TypeOf(left_state) = if (left_state == right_state)
                left_state
            else
                .maybe_alive;
            try joined.tracker.roots.append(.{ .id = id, .state = root_state });
        }
        for (left.places.items) |left_place| {
            var merged = left_place;
            if (findPlace(right.places.items, left_place.storage)) |right_place| {
                merged.initializedness = joinInitializedness(left_place.initializedness, right_place.initializedness);
                merged.value = try self.joinValueFacts(left_place.value, right_place.value);
            }
            try joined.places.append(merged);
        }
        for (right.places.items) |right_place| {
            if (findPlace(left.places.items, right_place.storage) == null) try joined.places.append(right_place);
        }
        var left_roots = left.storage_roots.iterator();
        while (left_roots.next()) |entry| try joined.storage_roots.put(entry.key_ptr.*, entry.value_ptr.*);
        var right_roots = right.storage_roots.iterator();
        while (right_roots.next()) |entry| if (!joined.storage_roots.contains(entry.key_ptr.*))
            try joined.storage_roots.put(entry.key_ptr.*, entry.value_ptr.*);
        joined.reachable = true;
        joined.ownership_conflict_reported = left.ownership_conflict_reported or right.ownership_conflict_reported;
        destination.deinit();
        destination.* = joined;
    }

    fn validateLoop(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        body: *const sg.CodeBlock,
        state: *FunctionState,
        increment: ?*const sg.SGNode,
    ) !void {
        var entry = try state.clone(self.allocator.*);
        defer entry.deinit();
        var current = try state.clone(self.allocator.*);
        defer current.deinit();
        for (0..8) |_| {
            var iteration = try current.clone(self.allocator.*);
            defer iteration.deinit();
            try self.validateBlock(function, body, &iteration);
            if (iteration.reachable) {
                if (increment) |node| _ = try self.evaluate(function, node, &iteration);
            }
            var next = try entry.clone(self.allocator.*);
            try self.joinStates(function, &next, &entry, &iteration);
            if (statesEqual(&current, &next)) {
                try self.copyState(state, &next);
                next.deinit();
                return;
            }
            current.deinit();
            current = next;
        }
        try self.copyState(state, &current);
    }

    fn aggregate(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        fields: []const sg.StructValueLiteralField,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        var dependencies = std.array_list.Managed(facts.ReferenceDependency).init(self.allocator.*);
        var owned_roots = std.array_list.Managed(facts.RootId).init(self.allocator.*);
        var field_facts = std.array_list.Managed(facts.FieldFacts).init(self.allocator.*);
        var contains_integer_address = false;
        var contains_foreign_storage = false;
        for (fields, 0..) |field, index| {
            const value = try self.evaluate(function, field.value, state);
            try dependencies.appendSlice(value.dependencies);
            try owned_roots.appendSlice(value.owned_roots);
            const stored = try self.allocator.create(facts.ValueFacts);
            stored.* = value;
            try field_facts.append(.{ .index = @intCast(index), .value = stored });
            contains_integer_address = contains_integer_address or value.integer_address;
            contains_foreign_storage = contains_foreign_storage or value.foreign_storage;
        }
        return .{
            .dependencies = try dependencies.toOwnedSlice(),
            .owned_roots = try owned_roots.toOwnedSlice(),
            .fields = try field_facts.toOwnedSlice(),
            .integer_address = contains_integer_address,
            .foreign_storage = contains_foreign_storage,
        };
    }

    fn storageRoot(self: *SafetyChecker, node: *const sg.SGNode, state: *FunctionState) !facts.RootId {
        _ = self;
        const binding = rootBinding(node) orelse return state.tracker.establish(.fresh);
        if (state.storage_roots.get(binding)) |root| return root;
        const root = try state.tracker.establish(.fresh);
        try state.storage_roots.put(binding, root);
        return root;
    }

    fn getPlace(self: *SafetyChecker, state: *FunctionState, storage: place.Place) ?*facts.PlaceFacts {
        _ = self;
        var index = state.places.items.len;
        while (index > 0) {
            index -= 1;
            if (state.places.items[index].storage.eql(storage)) return &state.places.items[index];
        }
        return null;
    }

    fn setPlace(
        self: *SafetyChecker,
        state: *FunctionState,
        storage: place.Place,
        initializedness: value_state.Initializedness,
        value: facts.ValueFacts,
    ) !void {
        if (self.getPlace(state, storage)) |existing| {
            existing.initializedness = initializedness;
            existing.value = value;
        } else {
            try state.places.append(.{ .storage = storage, .initializedness = initializedness, .value = value });
        }
        if (initializedness == .initialized) {
            var index = state.places.items.len;
            while (index > 0) {
                index -= 1;
                const candidate = &state.places.items[index];
                if (storage.eql(candidate.storage)) continue;
                if (storage.isPrefixOf(candidate.storage)) {
                    candidate.initializedness = .deinitialized;
                    candidate.value = .{};
                }
            }
        }
    }

    fn requireInitialized(self: *SafetyChecker, function: *const sg.FunctionDeclaration, place_facts: *const facts.PlaceFacts) !void {
        if (place_facts.initializedness == .initialized) return;
        try self.diagnostics.add(function.location, .semantic, "place rooted at '{s}' is {s} and cannot be used", .{
            place_facts.storage.root.name,
            @tagName(place_facts.initializedness),
        });
    }

    const OwnerLocation = struct {
        root: facts.RootId,
        storage: place.Place,
    };

    fn validateUniqueOwnership(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        state: *FunctionState,
    ) !void {
        if (state.ownership_conflict_reported) return;
        var owners = std.array_list.Managed(OwnerLocation).init(self.allocator.*);
        defer owners.deinit();
        for (state.places.items) |place_facts| {
            if (place_facts.initializedness != .initialized) continue;
            try self.collectOwnerLocations(place_facts.storage, place_facts.value, &owners);
        }
        for (owners.items, 0..) |owner, index| {
            for (owners.items[index + 1 ..]) |other| {
                if (owner.root != other.root or owner.storage.eql(other.storage)) continue;
                state.ownership_conflict_reported = true;
                try self.diagnostics.add(function.location, .semantic, "root ownership was duplicated across structural places", .{});
                return;
            }
        }
    }

    fn rejectEscapingLocalRoots(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        state: *const FunctionState,
    ) !void {
        for (function.output_bindings) |binding| {
            if (!typeContainsPointer(binding.ty)) continue;
            const output = findPlace(state.places.items, .{ .root = binding }) orelse continue;
            if (output.initializedness == .initialized)
                try self.rejectEscapingValue(function, output.value, state);
        }
    }

    fn rejectEscapingValue(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        value: facts.ValueFacts,
        state: *const FunctionState,
    ) !void {
        for (value.dependencies) |dependency| {
            if (!isLocalStorageRoot(function, state, dependency.root)) continue;
            try self.diagnostics.add(function.location, .semantic, "function output cannot depend on a local storage root that ends before return", .{});
            return;
        }
    }

    fn collectOwnerLocations(
        self: *SafetyChecker,
        storage: place.Place,
        value: facts.ValueFacts,
        result: *std.array_list.Managed(OwnerLocation),
    ) !void {
        for (value.owned_roots) |root| {
            var owned_by_field = false;
            for (value.fields) |field| if (valueContainsOwnedRoot(field.value.*, root)) {
                owned_by_field = true;
                break;
            };
            if (!owned_by_field) try result.append(.{ .root = root, .storage = storage });
        }
        for (value.fields) |field| {
            try self.collectOwnerLocations(
                try self.projectedPlace(storage, .{ .field = field.index }),
                field.value.*,
                result,
            );
        }
    }

    fn projectedPlace(self: *SafetyChecker, base: place.Place, projection: place.Projection) !place.Place {
        const projections = try self.allocator.alloc(place.Projection, base.projections.len + 1);
        @memcpy(projections[0..base.projections.len], base.projections);
        projections[base.projections.len] = projection;
        return .{ .root = base.root, .projections = projections };
    }

    fn resolvePlace(self: *SafetyChecker, node: *const sg.SGNode, state: *FunctionState) !?place.Place {
        return switch (node.content) {
            .binding_use => |binding| .{ .root = binding },
            .address_of => |value| try self.resolvePlace(value, state),
            .struct_field_access => |access| if (try self.resolvePlace(access.struct_value, state)) |base|
                try self.projectedPlace(base, .{ .field = access.field_index })
            else
                null,
            .array_index => |index| if (try self.resolvePlace(index.array_ptr, state)) |base|
                try self.projectedPlace(base, if (staticIndex(index.index)) |static_index|
                    .{ .static_index = static_index }
                else
                    .dynamic_index)
            else
                null,
            .dereference => |dereference| blk: {
                if (dereference.pointer.content == .address_of)
                    break :blk try self.resolvePlace(dereference.pointer.content.address_of, state);
                const pointer_storage = try self.resolvePlace(dereference.pointer, state) orelse break :blk null;
                const pointer_facts = self.getPlace(state, pointer_storage) orelse break :blk null;
                break :blk pointer_facts.value.referenced_place;
            },
            else => null,
        };
    }

    fn oneDependency(self: *SafetyChecker, root: facts.RootId) ![]const facts.ReferenceDependency {
        const result = try self.allocator.alloc(facts.ReferenceDependency, 1);
        result[0] = .{ .root = root };
        return result;
    }

    fn oneFreshSource(self: *SafetyChecker, source: facts.FreshRootSource) ![]const facts.FreshRootSource {
        const result = try self.allocator.alloc(facts.FreshRootSource, 1);
        result[0] = source;
        return result;
    }

    fn mergeFreshSources(
        self: *SafetyChecker,
        left: []const facts.FreshRootSource,
        right: []const facts.FreshRootSource,
    ) ![]const facts.FreshRootSource {
        var result = std.array_list.Managed(facts.FreshRootSource).init(self.allocator.*);
        for (left) |source| try appendFreshSource(&result, source);
        for (right) |source| try appendFreshSource(&result, source);
        return result.toOwnedSlice();
    }

    fn oneOwnedRoot(self: *SafetyChecker, root: facts.RootId) ![]const facts.RootId {
        const result = try self.allocator.alloc(facts.RootId, 1);
        result[0] = root;
        return result;
    }

    fn ensureEmptySummary(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !void {
        if (self.summaries.contains(function)) return;
        const outputs = try self.allocator.alloc(facts.OutputEffect, function.output.fields.len);
        @memset(outputs, .{});
        try self.summaries.put(function, .{ .outputs = outputs });
    }

    fn infer(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !bool {
        if (function.safety_primitive != .none)
            return self.replaceSingleOutput(function, try self.primitiveOutputEffect(function.safety_primitive, @intFromPtr(function)));
        const body = function.body orelse return false;
        const previous = self.summaries.get(function).?;
        const outputs = try self.allocator.dupe(facts.OutputEffect, previous.outputs);
        try self.inferBlock(function, body, outputs);
        var deinitialized = std.array_list.Managed(u32).init(self.allocator.*);
        try self.inferDeinitializedInputs(function, body, &deinitialized);
        const deinitialized_slice = try deinitialized.toOwnedSlice();
        if (effectsEqual(previous.outputs, outputs) and
            std.mem.eql(u32, previous.ends_input_roots, deinitialized_slice) and
            std.mem.eql(u32, previous.deinitializes_inputs, deinitialized_slice)) return false;
        try self.summaries.put(function, .{
            .outputs = outputs,
            .ends_input_roots = deinitialized_slice,
            .deinitializes_inputs = deinitialized_slice,
        });
        return true;
    }

    fn inferDeinitializedInputs(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        result: *std.array_list.Managed(u32),
    ) !void {
        var states = std.AutoHashMap(u32, bool).init(self.allocator.*);
        defer states.deinit();
        try self.inferInputInitializedness(function, block, &states);
        var iterator = states.iterator();
        while (iterator.next()) |entry| if (entry.value_ptr.*) try result.append(entry.key_ptr.*);
    }

    fn inferInputInitializedness(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        states: *std.AutoHashMap(u32, bool),
    ) !void {
        for (block.nodes) |node| switch (node.content) {
            .function_call => |call| {
                if (call.input.content != .struct_value_literal) continue;
                const arguments = call.input.content.struct_value_literal.fields;
                if (std.mem.eql(u8, call.callee.name, "deallocate")) {
                    if (arguments.len > 1) {
                        const effect = try self.inferExpression(function, arguments[1].value);
                        try setEffectInputState(effect, states, true);
                    }
                    continue;
                }
                const summary = self.summaries.get(call.callee) orelse continue;
                for (summary.ends_input_roots) |callee_index| {
                    if (callee_index < arguments.len)
                        try setEffectInputState(try self.inferExpression(function, arguments[callee_index].value), states, true);
                }
            },
            .pointer_assignment => |assignment| {
                try setEffectInputState(try self.inferExpression(function, assignment.pointer), states, false);
            },
            .if_statement => |statement| {
                var then_states = try cloneInputStates(states, self.allocator.*);
                defer then_states.deinit();
                try self.inferInputInitializedness(function, statement.then_block, &then_states);
                var else_states = try cloneInputStates(states, self.allocator.*);
                defer else_states.deinit();
                if (statement.else_block) |else_block| try self.inferInputInitializedness(function, else_block, &else_states);
                try joinInputStates(states, &then_states, &else_states);
            },
            .while_statement => |statement| {
                var body_states = try cloneInputStates(states, self.allocator.*);
                defer body_states.deinit();
                try self.inferInputInitializedness(function, statement.body, &body_states);
                var entry_states = try cloneInputStates(states, self.allocator.*);
                defer entry_states.deinit();
                try joinInputStates(states, &entry_states, &body_states);
            },
            .for_statement => |statement| {
                var body_states = try cloneInputStates(states, self.allocator.*);
                defer body_states.deinit();
                try self.inferInputInitializedness(function, statement.body, &body_states);
                var entry_states = try cloneInputStates(states, self.allocator.*);
                defer entry_states.deinit();
                try joinInputStates(states, &entry_states, &body_states);
            },
            else => {},
        };
    }

    fn replaceSingleOutput(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        effect: facts.OutputEffect,
    ) !bool {
        const previous = self.summaries.get(function).?;
        if (previous.outputs.len != 1 or std.meta.eql(previous.outputs[0], effect)) return false;
        const outputs = try self.allocator.alloc(facts.OutputEffect, 1);
        outputs[0] = effect;
        try self.summaries.put(function, .{ .outputs = outputs });
        return true;
    }

    fn inferBlock(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        outputs: []facts.OutputEffect,
    ) !void {
        for (block.nodes) |node| switch (node.content) {
            .binding_assignment => |assignment| {
                const output_index = bindingIndex(function.output_bindings, assignment.sym_id) orelse continue;
                outputs[output_index] = try self.inferExpression(function, assignment.value);
            },
            .if_statement => |statement| {
                try self.inferBlock(function, statement.then_block, outputs);
                if (statement.else_block) |else_block| try self.inferBlock(function, else_block, outputs);
            },
            .while_statement => |statement| try self.inferBlock(function, statement.body, outputs),
            .for_statement => |statement| try self.inferBlock(function, statement.body, outputs),
            .switch_statement => |statement| {
                for (statement.cases) |case| try self.inferBlock(function, case.body, outputs);
                if (statement.default_case) |default_case| try self.inferBlock(function, default_case, outputs);
            },
            else => {},
        };
    }

    fn inferExpression(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
    ) anyerror!facts.OutputEffect {
        return switch (node.content) {
            .binding_use => |binding| if (inputIndex(function, binding)) |index|
                try self.inputOutputEffect(@intCast(index), &.{})
            else
                .{},
            .move_value => |value| self.withOwnershipTransfer(try self.inferExpression(function, value)),
            .address_of => |value| try self.withoutOwnershipTransfer(try self.inferExpression(function, value)),
            .dereference => |value| try self.inferExpression(function, value.pointer),
            .struct_value_literal => |literal| try self.inferAggregate(function, literal.fields),
            .struct_field_access => |access| try self.inferProjection(function, access.struct_value, .{ .field = access.field_index }),
            .array_index => |index| try self.inferProjection(function, index.array_ptr, if (staticIndex(index.index)) |value| .{ .static_index = value } else .dynamic_index),
            .explicit_cast => |cast| try self.inferExpression(function, cast.value),
            .function_call => |call| try self.inferCall(function, call),
            .virtualize => |virtualize| try self.inferExpression(function, virtualize.value),
            .virtual_call => |call| try self.inferExpression(function, call.input),
            else => .{},
        };
    }

    fn inferCall(self: *SafetyChecker, function: *const sg.FunctionDeclaration, call: *const sg.FunctionCall) !facts.OutputEffect {
        if (call.callee.safety_primitive != .none) return self.primitiveOutputEffect(call.callee.safety_primitive, @intFromPtr(call));
        const callee_summary = self.summaries.get(call.callee) orelse return .{};
        if (callee_summary.outputs.len != 1 or call.input.content != .struct_value_literal) return .{};
        return self.substituteOutput(function, callee_summary.outputs[0], call.input.content.struct_value_literal.fields);
    }

    fn inputOutputEffect(self: *SafetyChecker, input_index: u32, projections: []const place.Projection) !facts.OutputEffect {
        const dependencies = try self.allocator.alloc(facts.InputDependency, 1);
        dependencies[0] = .{ .input_index = input_index, .projections = projections };
        return .{ .input_dependencies = dependencies };
    }

    fn primitiveOutputEffect(self: *SafetyChecker, primitive: sg.SafetyPrimitive, source: facts.FreshRootSource) !facts.OutputEffect {
        return switch (primitive) {
            .none => .{},
            .establish_fresh_reference => .{ .fresh_dependencies = try self.oneFreshSource(source) },
            .establish_inherited_reference => self.inputOutputEffect(1, &.{}),
            .establish_allocation => self.ownedAllocationEffect(source),
            .reference_offset,
            .mutable_reference_offset,
            .reinterpret_reference,
            .mutable_reinterpret_reference,
            .read_reference,
            => self.inputOutputEffect(0, &.{}),
        };
    }

    fn ownedAllocationEffect(self: *SafetyChecker, source: facts.FreshRootSource) !facts.OutputEffect {
        const fields = try self.allocator.alloc(facts.OutputFieldEffect, 2);
        const data = try self.allocator.create(facts.OutputEffect);
        data.* = .{ .fresh_dependencies = try self.oneFreshSource(source) };
        const size = try self.allocator.create(facts.OutputEffect);
        size.* = .{};
        fields[0] = .{ .index = 0, .value = data };
        fields[1] = .{ .index = 1, .value = size };
        return .{
            .fresh_owned_roots = try self.oneFreshSource(source),
            .fields = fields,
        };
    }

    fn withOwnershipTransfer(self: *SafetyChecker, effect: facts.OutputEffect) facts.OutputEffect {
        _ = self;
        for (effect.input_dependencies) |*dependency| @constCast(dependency).transfers_ownership = true;
        return effect;
    }

    fn withoutOwnershipTransfer(self: *SafetyChecker, effect: facts.OutputEffect) !facts.OutputEffect {
        const dependencies = try self.allocator.dupe(facts.InputDependency, effect.input_dependencies);
        for (dependencies) |*dependency| dependency.transfers_ownership = false;
        var result = effect;
        result.input_dependencies = dependencies;
        return result;
    }

    fn inferAggregate(self: *SafetyChecker, function: *const sg.FunctionDeclaration, fields: []const sg.StructValueLiteralField) !facts.OutputEffect {
        const output_fields = try self.allocator.alloc(facts.OutputFieldEffect, fields.len);
        var result: facts.OutputEffect = .{};
        for (fields, 0..) |field, index| {
            const value = try self.allocator.create(facts.OutputEffect);
            value.* = try self.inferExpression(function, field.value);
            output_fields[index] = .{ .index = @intCast(index), .value = value };
            result = try self.mergeOutputEffects(result, value.*);
        }
        result.fields = output_fields;
        return result;
    }

    fn inferProjection(self: *SafetyChecker, function: *const sg.FunctionDeclaration, base_node: *const sg.SGNode, projection: place.Projection) !facts.OutputEffect {
        return self.projectOutputEffect(try self.inferExpression(function, base_node), projection);
    }

    fn projectOutputEffect(self: *SafetyChecker, effect: facts.OutputEffect, projection: place.Projection) !facts.OutputEffect {
        if (projection == .field) {
            for (effect.fields) |field| if (field.index == projection.field) return field.value.*;
        }
        const dependencies = try self.allocator.alloc(facts.InputDependency, effect.input_dependencies.len);
        for (effect.input_dependencies, 0..) |dependency, index| {
            const projections = try self.allocator.alloc(place.Projection, dependency.projections.len + 1);
            @memcpy(projections[0..dependency.projections.len], dependency.projections);
            projections[dependency.projections.len] = projection;
            dependencies[index] = dependency;
            dependencies[index].projections = projections;
        }
        return .{
            .input_dependencies = dependencies,
            .fresh_dependencies = effect.fresh_dependencies,
            .fresh_owned_roots = effect.fresh_owned_roots,
            .integer_address = effect.integer_address,
            .foreign_storage = effect.foreign_storage,
        };
    }

    fn substituteOutput(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        effect: facts.OutputEffect,
        arguments: []const sg.StructValueLiteralField,
    ) !facts.OutputEffect {
        var result: facts.OutputEffect = .{
            .fresh_dependencies = effect.fresh_dependencies,
            .fresh_owned_roots = effect.fresh_owned_roots,
            .integer_address = effect.integer_address,
            .foreign_storage = effect.foreign_storage,
        };
        for (effect.input_dependencies) |dependency| {
            if (dependency.input_index >= arguments.len) continue;
            var argument = try self.inferExpression(function, arguments[dependency.input_index].value);
            for (dependency.projections) |projection| argument = try self.projectOutputEffect(argument, projection);
            if (dependency.transfers_ownership) argument = self.withOwnershipTransfer(argument) else argument = try self.withoutOwnershipTransfer(argument);
            result = try self.mergeOutputEffects(result, argument);
        }
        if (effect.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
            for (effect.fields, 0..) |field, index| {
                const value = try self.allocator.create(facts.OutputEffect);
                value.* = try self.substituteOutput(function, field.value.*, arguments);
                fields[index] = .{ .index = field.index, .value = value };
            }
            result.fields = fields;
        }
        return result;
    }

    fn mergeOutputEffects(self: *SafetyChecker, left: facts.OutputEffect, right: facts.OutputEffect) !facts.OutputEffect {
        var dependencies = std.array_list.Managed(facts.InputDependency).init(self.allocator.*);
        for (left.input_dependencies) |dependency| try appendInputDependency(&dependencies, dependency);
        for (right.input_dependencies) |dependency| try appendInputDependency(&dependencies, dependency);
        return .{
            .input_dependencies = try dependencies.toOwnedSlice(),
            .fresh_dependencies = try self.mergeFreshSources(left.fresh_dependencies, right.fresh_dependencies),
            .fresh_owned_roots = try self.mergeFreshSources(left.fresh_owned_roots, right.fresh_owned_roots),
            .integer_address = left.integer_address or right.integer_address,
            .foreign_storage = left.foreign_storage or right.foreign_storage,
        };
    }
};

fn bindingIndex(bindings: []const *const sg.BindingDeclaration, target: *const sg.BindingDeclaration) ?usize {
    for (bindings, 0..) |binding, index| {
        if (binding == target or std.mem.eql(u8, binding.name, target.name)) return index;
    }
    return null;
}

fn findPlace(places: []const facts.PlaceFacts, storage: place.Place) ?*const facts.PlaceFacts {
    for (places) |*candidate| if (candidate.storage.eql(storage)) return candidate;
    return null;
}

fn findField(fields: []const facts.FieldFacts, index: u32) ?facts.FieldFacts {
    for (fields) |field| if (field.index == index) return field;
    return null;
}

fn containsRoot(roots: []const facts.RootId, target: facts.RootId) bool {
    for (roots) |root| if (root == target) return true;
    return false;
}

fn valueContainsOwnedRoot(value: facts.ValueFacts, target: facts.RootId) bool {
    if (containsRoot(value.owned_roots, target)) return true;
    for (value.fields) |field| if (valueContainsOwnedRoot(field.value.*, target)) return true;
    return false;
}

fn isLocalStorageRoot(
    function: *const sg.FunctionDeclaration,
    state: *const SafetyChecker.FunctionState,
    root: facts.RootId,
) bool {
    var iterator = state.storage_roots.iterator();
    while (iterator.next()) |entry| {
        if (entry.value_ptr.* != root) continue;
        return bindingIndex(function.input_bindings, entry.key_ptr.*) == null;
    }
    return false;
}

fn typeContainsPointer(ty: sg.Type) bool {
    return switch (ty) {
        .pointer_type => true,
        .array_type => |array| typeContainsPointer(array.element_type.*),
        .struct_type => |struct_type| blk: {
            for (struct_type.fields) |field| if (typeContainsPointer(field.ty)) break :blk true;
            break :blk false;
        },
        .choice_type => |choice| blk: {
            for (choice.variants) |variant| if (variant.payload_type) |payload|
                if (typeContainsPointer(payload)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

fn joinInitializedness(left: value_state.Initializedness, right: value_state.Initializedness) value_state.Initializedness {
    if (left == right) return left;
    return .maybe_initialized;
}

fn statesEqual(left: *const SafetyChecker.FunctionState, right: *const SafetyChecker.FunctionState) bool {
    if (left.reachable != right.reachable or
        left.ownership_conflict_reported != right.ownership_conflict_reported or
        left.tracker.roots.items.len != right.tracker.roots.items.len or
        left.places.items.len != right.places.items.len) return false;
    for (left.tracker.roots.items, right.tracker.roots.items) |a, b| if (a.state != b.state) return false;
    for (left.places.items) |left_place| {
        const right_place = findPlace(right.places.items, left_place.storage) orelse return false;
        if (left_place.initializedness != right_place.initializedness or !valueFactsEqual(left_place.value, right_place.value)) return false;
    }
    return true;
}

fn valueFactsEqual(left: facts.ValueFacts, right: facts.ValueFacts) bool {
    if (left.integer_address != right.integer_address or
        left.foreign_storage != right.foreign_storage or
        left.dependencies.len != right.dependencies.len or
        left.owned_roots.len != right.owned_roots.len or
        left.fields.len != right.fields.len) return false;
    for (left.dependencies, right.dependencies) |a, b| if (a.root != b.root) return false;
    for (left.owned_roots, right.owned_roots) |a, b| if (a != b) return false;
    if ((left.referenced_place == null) != (right.referenced_place == null)) return false;
    if (left.referenced_place) |left_place| if (!left_place.eql(right.referenced_place.?)) return false;
    for (left.fields, right.fields) |a, b| if (a.index != b.index or !valueFactsEqual(a.value.*, b.value.*)) return false;
    return true;
}

fn inputIndex(function: *const sg.FunctionDeclaration, target: *const sg.BindingDeclaration) ?usize {
    if (bindingIndex(function.input_bindings, target)) |index| return index;
    for (function.input.fields, 0..) |field, index| {
        if (std.mem.eql(u8, field.name, target.name)) return index;
    }
    return null;
}

fn effectsEqual(left: []const facts.OutputEffect, right: []const facts.OutputEffect) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!outputEffectEqual(a, b)) return false;
    return true;
}

fn appendEffectInput(effect: facts.OutputEffect, result: *std.array_list.Managed(u32)) !void {
    for (effect.input_dependencies) |dependency| {
        var found = false;
        for (result.items) |existing| if (existing == dependency.input_index) {
            found = true;
            break;
        };
        if (found) continue;
        try result.append(dependency.input_index);
    }
}

fn setEffectInputState(
    effect: facts.OutputEffect,
    states: *std.AutoHashMap(u32, bool),
    deinitialized: bool,
) !void {
    for (effect.input_dependencies) |dependency|
        try states.put(dependency.input_index, deinitialized);
}

fn cloneInputStates(source: *const std.AutoHashMap(u32, bool), allocator: std.mem.Allocator) !std.AutoHashMap(u32, bool) {
    var result = std.AutoHashMap(u32, bool).init(allocator);
    var iterator = source.iterator();
    while (iterator.next()) |entry| try result.put(entry.key_ptr.*, entry.value_ptr.*);
    return result;
}

fn joinInputStates(
    destination: *std.AutoHashMap(u32, bool),
    left: *const std.AutoHashMap(u32, bool),
    right: *const std.AutoHashMap(u32, bool),
) !void {
    destination.clearRetainingCapacity();
    var left_iterator = left.iterator();
    while (left_iterator.next()) |entry|
        try destination.put(entry.key_ptr.*, entry.value_ptr.* or (right.get(entry.key_ptr.*) orelse false));
    var right_iterator = right.iterator();
    while (right_iterator.next()) |entry| if (!destination.contains(entry.key_ptr.*))
        try destination.put(entry.key_ptr.*, entry.value_ptr.*);
}

fn projectValueFacts(value: facts.ValueFacts, projections: []const place.Projection) facts.ValueFacts {
    var current = value;
    for (projections) |projection| switch (projection) {
        .field => |index| {
            for (current.fields) |field| if (field.index == index) {
                current = field.value.*;
                break;
            };
        },
        .static_index => |index| {
            for (current.fields) |field| if (field.index == index) {
                current = field.value.*;
                break;
            };
        },
        .dynamic_index, .dereference => {},
    };
    return current;
}

fn appendDependency(list: *std.array_list.Managed(facts.ReferenceDependency), dependency: facts.ReferenceDependency) !void {
    for (list.items) |existing| if (existing.root == dependency.root) return;
    try list.append(dependency);
}

fn appendOwnedRoot(list: *std.array_list.Managed(facts.RootId), owned_root: facts.RootId) !void {
    for (list.items) |existing| if (existing == owned_root) return;
    try list.append(owned_root);
}

fn appendInputDependency(list: *std.array_list.Managed(facts.InputDependency), dependency: facts.InputDependency) !void {
    for (list.items) |existing| {
        if (existing.input_index != dependency.input_index or existing.transfers_ownership != dependency.transfers_ownership) continue;
        if (projectionsEqual(existing.projections, dependency.projections)) return;
    }
    try list.append(dependency);
}

fn appendFreshSource(list: *std.array_list.Managed(facts.FreshRootSource), source: facts.FreshRootSource) !void {
    for (list.items) |existing| if (existing == source) return;
    try list.append(source);
}

fn projectionsEqual(left: []const place.Projection, right: []const place.Projection) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!a.eql(b)) return false;
    return true;
}

fn outputEffectEqual(left: facts.OutputEffect, right: facts.OutputEffect) bool {
    if (left.integer_address != right.integer_address or
        left.foreign_storage != right.foreign_storage or
        !std.mem.eql(facts.FreshRootSource, left.fresh_dependencies, right.fresh_dependencies) or
        !std.mem.eql(facts.FreshRootSource, left.fresh_owned_roots, right.fresh_owned_roots)) return false;
    if (left.input_dependencies.len != right.input_dependencies.len or left.fields.len != right.fields.len) return false;
    for (left.input_dependencies, right.input_dependencies) |a, b| {
        if (a.input_index != b.input_index or a.transfers_ownership != b.transfers_ownership or !projectionsEqual(a.projections, b.projections)) return false;
    }
    for (left.fields, right.fields) |a, b| {
        if (a.index != b.index or !outputEffectEqual(a.value.*, b.value.*)) return false;
    }
    return true;
}

fn rootBinding(node: *const sg.SGNode) ?*const sg.BindingDeclaration {
    return switch (node.content) {
        .binding_use => |binding| binding,
        .struct_field_access => |access| rootBinding(access.struct_value),
        .array_index => |index| rootBinding(index.array_ptr),
        .dereference => |dereference| rootBinding(dereference.pointer),
        .address_of => |value| rootBinding(value),
        else => null,
    };
}

fn staticIndex(node: *const sg.SGNode) ?usize {
    if (node.content != .value_literal) return null;
    return switch (node.content.value_literal) {
        .int_literal => |index| if (index >= 0) @intCast(index) else null,
        else => null,
    };
}
