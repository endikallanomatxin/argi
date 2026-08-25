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
    };

    fn validateFunction(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !void {
        const body = function.body orelse return;
        if (function.origin_kind != .declared) return;
        if (isRootingPrimitive(function.name)) return;
        if (std.mem.indexOf(u8, function.location.file, "core/") != null) return;
        var state = FunctionState.init(self.allocator.*);
        defer state.deinit();
        for (function.input_bindings) |binding| {
            if (binding.ty == .pointer_type) {
                const root = try state.tracker.establish(.fresh);
                try self.setPlace(&state, .{ .root = binding }, .initialized, .{ .dependencies = try self.oneDependency(root) });
            } else {
                try self.setPlace(&state, .{ .root = binding }, .initialized, .{});
            }
        }
        try self.validateBlock(function, body, &state);
    }

    fn validateBlock(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        state: *FunctionState,
    ) !void {
        for (block.nodes) |node| switch (node.content) {
            .binding_declaration => |binding| {
                const value = if (binding.initialization) |initialization|
                    try self.evaluate(function, initialization, state)
                else
                    facts.ValueFacts{};
                try self.setPlace(state, .{ .root = binding }, .initialized, value);
            },
            .binding_assignment => |assignment| {
                try self.setPlace(state, .{ .root = assignment.sym_id }, .initialized, try self.evaluate(function, assignment.value, state));
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
                try self.validateBlock(function, statement.then_block, state);
                if (statement.else_block) |else_block| try self.validateBlock(function, else_block, state);
            },
            .while_statement => |statement| {
                _ = try self.evaluate(function, statement.condition, state);
                try self.validateBlock(function, statement.body, state);
            },
            .for_statement => |statement| {
                if (statement.init) |initialization| _ = try self.evaluate(function, initialization, state);
                _ = try self.evaluate(function, statement.condition, state);
                try self.validateBlock(function, statement.body, state);
                if (statement.increment) |increment| _ = try self.evaluate(function, increment, state);
            },
            .return_statement => |statement| if (statement.expression) |expression| {
                _ = try self.evaluate(function, expression, state);
            },
            else => {},
        };
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
                if (target_is_integer and source_is_reference)
                    break :blk facts.ValueFacts{ .integer_address = true };
                if (target_is_reference and !target_is_raw_any and value.integer_address) {
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
        if (std.mem.eql(u8, call.callee.name, "deallocate") and arguments.len > 1) {
            const data = try self.evaluate(function, arguments[1].value, state);
            for (data.dependencies) |dependency| state.tracker.end(dependency.root);
            return .{};
        }
        const summary = self.summaries.get(call.callee) orelse return .{};
        for (summary.ends_input_roots) |index| {
            if (index >= arguments.len) continue;
            if (try self.resolvePlace(arguments[index].value, state)) |storage| {
                if (self.getPlace(state, storage)) |place_facts| {
                    for (place_facts.value.cleanup_responsibilities) |responsibility| state.tracker.end(responsibility.root);
                    var remaining = place_facts.value;
                    remaining.cleanup_responsibilities = &.{};
                    try self.setPlace(state, storage, .initialized, remaining);
                }
            }
        }
        if (summary.outputs.len != 1) return .{};
        return switch (summary.outputs[0]) {
            .independent => .{},
            .fresh => blk: {
                const root = try state.tracker.establish(.fresh);
                break :blk .{
                    .dependencies = try self.oneDependency(root),
                    .cleanup_responsibilities = try self.oneResponsibility(root),
                };
            },
            .depends_on_input, .transfers_input => |index| if (index < arguments.len)
                try self.evaluate(function, arguments[index].value, state)
            else
                .{},
        };
    }

    fn aggregate(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        fields: []const sg.StructValueLiteralField,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        var dependencies = std.array_list.Managed(facts.ReferenceDependency).init(self.allocator.*);
        var responsibilities = std.array_list.Managed(facts.CleanupResponsibility).init(self.allocator.*);
        var field_facts = std.array_list.Managed(facts.FieldFacts).init(self.allocator.*);
        var contains_integer_address = false;
        for (fields, 0..) |field, index| {
            const value = try self.evaluate(function, field.value, state);
            try dependencies.appendSlice(value.dependencies);
            try responsibilities.appendSlice(value.cleanup_responsibilities);
            const stored = try self.allocator.create(facts.ValueFacts);
            stored.* = value;
            try field_facts.append(.{ .index = @intCast(index), .value = stored });
            contains_integer_address = contains_integer_address or value.integer_address;
        }
        return .{
            .dependencies = try dependencies.toOwnedSlice(),
            .cleanup_responsibilities = try responsibilities.toOwnedSlice(),
            .fields = try field_facts.toOwnedSlice(),
            .integer_address = contains_integer_address,
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

    fn oneResponsibility(self: *SafetyChecker, root: facts.RootId) ![]const facts.CleanupResponsibility {
        const result = try self.allocator.alloc(facts.CleanupResponsibility, 1);
        result[0] = .{ .root = root };
        return result;
    }

    fn ensureEmptySummary(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !void {
        if (self.summaries.contains(function)) return;
        const outputs = try self.allocator.alloc(facts.OutputEffect, function.output.fields.len);
        @memset(outputs, .independent);
        try self.summaries.put(function, .{ .outputs = outputs });
    }

    fn infer(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !bool {
        if (std.mem.eql(u8, function.name, "establish_fresh_reference"))
            return self.replaceSingleOutput(function, .fresh);
        if (std.mem.eql(u8, function.name, "establish_inherited_reference"))
            return self.replaceSingleOutput(function, .{ .depends_on_input = 1 });
        const body = function.body orelse return false;
        const previous = self.summaries.get(function).?;
        const outputs = try self.allocator.dupe(facts.OutputEffect, previous.outputs);
        try self.inferBlock(function, body, outputs);
        var deinitialized = std.array_list.Managed(u32).init(self.allocator.*);
        try self.inferDeinitializedInputs(function, body, &deinitialized);
        const deinitialized_slice = try deinitialized.toOwnedSlice();
        if (effectsEqual(previous.outputs, outputs) and
            std.mem.eql(u32, previous.ends_input_roots, deinitialized_slice)) return false;
        try self.summaries.put(function, .{
            .outputs = outputs,
            .ends_input_roots = deinitialized_slice,
        });
        return true;
    }

    fn inferDeinitializedInputs(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        result: *std.array_list.Managed(u32),
    ) !void {
        for (block.nodes) |node| switch (node.content) {
            .function_call => |call| {
                if (call.input.content != .struct_value_literal) continue;
                const arguments = call.input.content.struct_value_literal.fields;
                if (std.mem.eql(u8, call.callee.name, "deallocate")) {
                    if (arguments.len > 1) {
                        const effect = self.inferExpression(function, arguments[1].value);
                        try appendEffectInput(effect, result);
                    }
                    continue;
                }
                const summary = self.summaries.get(call.callee) orelse continue;
                for (summary.ends_input_roots) |callee_index| {
                    if (callee_index < arguments.len)
                        try appendEffectInput(self.inferExpression(function, arguments[callee_index].value), result);
                }
            },
            .if_statement => |statement| {
                try self.inferDeinitializedInputs(function, statement.then_block, result);
                if (statement.else_block) |else_block| try self.inferDeinitializedInputs(function, else_block, result);
            },
            .while_statement => |statement| try self.inferDeinitializedInputs(function, statement.body, result),
            .for_statement => |statement| try self.inferDeinitializedInputs(function, statement.body, result),
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
                outputs[output_index] = self.inferExpression(function, assignment.value);
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
    ) facts.OutputEffect {
        return switch (node.content) {
            .binding_use => |binding| if (inputIndex(function, binding)) |index|
                .{ .depends_on_input = @intCast(index) }
            else
                .independent,
            .move_value => |value| switch (self.inferExpression(function, value)) {
                .depends_on_input => |index| .{ .transfers_input = index },
                else => |effect| effect,
            },
            .address_of => |value| self.inferExpression(function, value),
            .dereference => |value| self.inferExpression(function, value.pointer),
            .struct_field_access => |access| self.inferExpression(function, access.struct_value),
            .explicit_cast => |cast| self.inferExpression(function, cast.value),
            .function_call => |call| self.inferCall(function, call),
            .virtualize => |virtualize| self.inferExpression(function, virtualize.value),
            .virtual_call => |call| self.inferExpression(function, call.input),
            else => .independent,
        };
    }

    fn inferCall(self: *SafetyChecker, function: *const sg.FunctionDeclaration, call: *const sg.FunctionCall) facts.OutputEffect {
        if (std.mem.eql(u8, call.callee.name, "establish_fresh_reference")) return .fresh;
        const callee_summary = self.summaries.get(call.callee) orelse return .independent;
        if (callee_summary.outputs.len != 1) return .independent;
        const effect = callee_summary.outputs[0];
        const input_index = switch (effect) {
            .depends_on_input => |index| index,
            .transfers_input => |index| index,
            else => return effect,
        };
        if (call.input.content != .struct_value_literal or input_index >= call.input.content.struct_value_literal.fields.len)
            return .independent;
        const argument = call.input.content.struct_value_literal.fields[input_index].value;
        const caller_effect = self.inferExpression(function, argument);
        return if (effect == .transfers_input) switch (caller_effect) {
            .depends_on_input => |index| .{ .transfers_input = index },
            else => caller_effect,
        } else caller_effect;
    }
};

fn bindingIndex(bindings: []const *const sg.BindingDeclaration, target: *const sg.BindingDeclaration) ?usize {
    for (bindings, 0..) |binding, index| {
        if (binding == target or std.mem.eql(u8, binding.name, target.name)) return index;
    }
    return null;
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
    for (left, right) |a, b| if (!std.meta.eql(a, b)) return false;
    return true;
}

fn appendEffectInput(effect: facts.OutputEffect, result: *std.array_list.Managed(u32)) !void {
    const index = switch (effect) {
        .depends_on_input, .transfers_input => |input| input,
        else => return,
    };
    for (result.items) |existing| if (existing == index) return;
    try result.append(index);
}

fn isRootingPrimitive(name: []const u8) bool {
    return std.mem.eql(u8, name, "establish_fresh_reference") or
        std.mem.eql(u8, name, "establish_inherited_reference");
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
