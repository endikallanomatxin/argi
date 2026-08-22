const std = @import("std");

const diagnostics = @import("../1_base/diagnostic.zig");
const sg = @import("semantic_graph.zig");
const temporal_place = @import("temporal_place.zig");
const typ = @import("types.zig");

const CapturedPlace = struct {
    place: temporal_place.Place,
    capture_sequence: u64,
    value_path: []const temporal_place.Projection = &.{},
};

const ReferenceFact = struct {
    captured: []const CapturedPlace,
};

const Invalidation = struct {
    place: temporal_place.Place,
    location: @import("../2_tokens/token.zig").Location,
    sequence: u64,
};

const FunctionState = struct {
    references: std.AutoHashMap(*const sg.BindingDeclaration, ReferenceFact),
    invalidations: std.array_list.Managed(Invalidation),

    fn init(allocator: std.mem.Allocator) FunctionState {
        return .{
            .references = std.AutoHashMap(*const sg.BindingDeclaration, ReferenceFact).init(allocator),
            .invalidations = std.array_list.Managed(Invalidation).init(allocator),
        };
    }

    fn deinit(self: *FunctionState) void {
        self.references.deinit();
        self.invalidations.deinit();
    }

    fn clone(self: *const FunctionState, allocator: std.mem.Allocator) !FunctionState {
        var result = FunctionState.init(allocator);
        errdefer result.deinit();

        var reference_it = self.references.iterator();
        while (reference_it.next()) |entry| try result.references.put(entry.key_ptr.*, entry.value_ptr.*);
        try result.invalidations.appendSlice(self.invalidations.items);
        return result;
    }
};

/// Runs after semantizing has produced complete function bodies and before any
/// consumer can hand the graph to codegen. Temporal properties intentionally
/// live here instead of being folded into type checking: source types describe
/// reference permissions, while this pass reasons about the identities those
/// references capture at particular program points.
pub const MemorySafetyAnalyzer = struct {
    allocator: *const std.mem.Allocator,
    diags: *diagnostics.Diagnostics,
    analyzed_functions: std.AutoHashMap(*const sg.FunctionDeclaration, void),
    summarizing_functions: std.AutoHashMap(*const sg.FunctionDeclaration, void),
    reported_uses: std.AutoHashMap(*const sg.SGNode, void),
    fresh_storage_roots: std.AutoHashMap(*const sg.FunctionCall, *const sg.BindingDeclaration),
    next_sequence: u64 = 1,
    inferring_summaries: bool = false,

    pub fn init(
        allocator: *const std.mem.Allocator,
        diags: *diagnostics.Diagnostics,
    ) MemorySafetyAnalyzer {
        return .{
            .allocator = allocator,
            .diags = diags,
            .analyzed_functions = std.AutoHashMap(*const sg.FunctionDeclaration, void).init(allocator.*),
            .summarizing_functions = std.AutoHashMap(*const sg.FunctionDeclaration, void).init(allocator.*),
            .reported_uses = std.AutoHashMap(*const sg.SGNode, void).init(allocator.*),
            .fresh_storage_roots = std.AutoHashMap(*const sg.FunctionCall, *const sg.BindingDeclaration).init(allocator.*),
        };
    }

    pub fn deinit(self: *MemorySafetyAnalyzer) void {
        self.analyzed_functions.deinit();
        self.summarizing_functions.deinit();
        self.reported_uses.deinit();
        self.fresh_storage_roots.deinit();
    }

    pub fn analyze(self: *MemorySafetyAnalyzer, nodes: []const *sg.SGNode) !void {
        var functions = std.array_list.Managed(*const sg.FunctionDeclaration).init(self.allocator.*);
        defer functions.deinit();
        for (nodes) |node| switch (node.content) {
            .function_declaration => |function| try functions.append(function),
            .test_declaration => |test_decl| try functions.append(test_decl.function),
            else => {},
        };

        self.inferring_summaries = true;
        defer self.inferring_summaries = false;
        const iteration_limit = @min(functions.items.len + 1, 32);
        for (0..iteration_limit) |_| {
            var changed = false;
            for (functions.items) |function| changed = (try self.inferFunctionSummaryPass(function)) or changed;
            if (!changed) break;
        }
        self.inferring_summaries = false;

        for (functions.items) |function| try self.analyzeFunction(function);
    }

    fn inferFunctionSummaryPass(self: *MemorySafetyAnalyzer, function: *const sg.FunctionDeclaration) !bool {
        const body = function.body orelse return false;
        if (self.summarizing_functions.contains(function)) return false;
        try self.summarizing_functions.put(function, {});
        defer _ = self.summarizing_functions.remove(function);
        const previous = function.temporal_summary;
        var state = FunctionState.init(self.allocator.*);
        defer state.deinit();
        try self.seedInputDependencies(function, &state);
        try self.analyzeCodeBlock(body, &state);
        try self.inferTemporalSummary(function, &state);
        return !temporalSummariesEqual(previous, function.temporal_summary);
    }

    pub fn analyzeFunction(self: *MemorySafetyAnalyzer, function: *const sg.FunctionDeclaration) !void {
        if (self.analyzed_functions.contains(function)) return;
        try self.analyzed_functions.put(function, {});

        const body = function.body orelse return;
        var state = FunctionState.init(self.allocator.*);
        defer state.deinit();
        try self.seedInputDependencies(function, &state);
        try self.analyzeCodeBlock(body, &state);
    }

    fn analyzeCodeBlock(self: *MemorySafetyAnalyzer, block: *const sg.CodeBlock, state: *FunctionState) anyerror!void {
        for (block.nodes) |node| try self.analyzeNode(node, state);
        if (block.ret_val) |value| try self.analyzeNode(value, state);
    }

    fn analyzeNode(self: *MemorySafetyAnalyzer, node: *const sg.SGNode, state: *FunctionState) anyerror!void {
        switch (node.content) {
            .binding_declaration => |binding| {
                if (binding.initialization) |initialization| {
                    if (initialization.content == .move_value)
                        try self.analyzeNode(initialization.content.move_value, state)
                    else
                        try self.analyzeNode(initialization, state);
                    try self.updateReferenceFact(binding, initialization, state);
                }
            },
            .binding_assignment => |assignment| {
                try self.analyzeNode(assignment.value, state);
                try self.recordInvalidation(.{
                    .root = assignment.sym_id,
                    .projections = &.{},
                }, node.location, state);
                try self.updateReferenceFact(assignment.sym_id, assignment.value, state);
            },
            .binding_use => |binding| try self.validateReferenceUse(binding, node, state),
            .move_value => |inner| {
                try self.analyzeNode(inner, state);
                try self.validateMoveRelocation(inner, node, state);
            },
            .function_call => |call| {
                try self.analyzeNode(call.input, state);
                try self.recordConservativeCallInvalidations(call, node, state);
            },
            .code_block => |block| try self.analyzeCodeBlock(block, state),
            .struct_value_literal => |value| for (value.fields) |field| try self.analyzeNode(field.value, state),
            .list_literal => |value| for (value.elements) |element| try self.analyzeNode(element, state),
            .array_literal => |value| for (value.elements) |element| try self.analyzeNode(element, state),
            .choice_literal => |value| if (value.payload) |payload| try self.analyzeNode(payload, state),
            .struct_field_access => |access| {
                if (access.struct_value.content == .dereference)
                    try self.analyzeNode(access.struct_value, state);
                try self.validateExpressionUse(node, state);
            },
            .choice_payload_access => |access| {
                if (access.choice_value.content == .dereference)
                    try self.analyzeNode(access.choice_value, state);
                try self.validateExpressionUse(node, state);
            },
            .array_index => |access| {
                if (access.array_ptr.content == .dereference)
                    try self.analyzeNode(access.array_ptr, state);
                try self.validateExpressionUse(node, state);
                try self.analyzeNode(access.index, state);
            },
            .dereference => |access| try self.analyzeNode(access.pointer, state),
            .address_of => {},
            .array_store => |store| {
                try self.analyzeNode(store.array_ptr, state);
                try self.analyzeNode(store.index, state);
                try self.analyzeNode(store.value, state);
                if (try temporal_place.Place.fromNode(store.array_ptr, self.allocator)) |base_place| {
                    const place = try temporal_place.Place.withProjection(
                        base_place,
                        .{ .array_index = constantIndex(store.index) },
                        self.allocator,
                    );
                    try self.recordInvalidation(place, node.location, state);
                }
            },
            .struct_field_store => |store| {
                try self.analyzeNode(store.struct_ptr, state);
                try self.analyzeNode(store.value, state);
                if (try temporal_place.Place.fromNode(store.struct_ptr, self.allocator)) |base_place| {
                    const place = try temporal_place.Place.withProjection(
                        base_place,
                        .{ .field = store.field_index },
                        self.allocator,
                    );
                    try self.recordInvalidation(place, node.location, state);
                    try self.updateStoredFieldFact(base_place.root, store.field_index, store.value, state);
                }
            },
            .pointer_assignment => |assignment| {
                try self.analyzeNode(assignment.pointer, state);
                try self.analyzeNode(assignment.value, state);
                if (assignment.pointer.sem_type) |pointer_ty| {
                    if (pointer_ty == .pointer_type and pointer_ty.pointer_type.mutability == .exclusive) {
                        if (try self.referenceFactFromValue(assignment.pointer, state)) |fact| {
                            for (fact.captured) |captured| {
                                if (assignment.value.content == .struct_value_literal and pointer_ty.pointer_type.child.* == .struct_type) {
                                    for (assignment.value.content.struct_value_literal.fields, 0..) |field, field_index| {
                                        if (fieldCopiesSameReferentField(field.value, assignment.pointer, @intCast(field_index))) continue;
                                        const place = try temporal_place.Place.withProjection(
                                            captured.place,
                                            .{ .field = @intCast(field_index) },
                                            self.allocator,
                                        );
                                        try self.recordInvalidation(place, node.location, state);
                                    }
                                } else {
                                    try self.recordInvalidation(captured.place, node.location, state);
                                }
                            }
                        }
                    }
                }
            },
            .binary_operation => |operation| {
                try self.analyzeNode(operation.left, state);
                try self.analyzeNode(operation.right, state);
            },
            .comparison => |comparison| {
                try self.analyzeNode(comparison.left, state);
                try self.analyzeNode(comparison.right, state);
            },
            .logical_operation => |operation| {
                try self.analyzeNode(operation.left, state);
                try self.analyzeNode(operation.right, state);
            },
            .if_statement => |statement| try self.analyzeIf(statement, state),
            .while_statement => |statement| try self.analyzeWhile(statement, state),
            .for_statement => |statement| try self.analyzeFor(statement, state),
            .switch_statement => |statement| try self.analyzeSwitch(statement, state),
            .return_statement => |statement| {
                if (statement.expression) |expression| try self.analyzeNode(expression, state);
                for (statement.cleanup_nodes) |cleanup| try self.analyzeNode(cleanup, state);
            },
            .nullable_unwrap_or => |unwrap| {
                try self.analyzeNode(unwrap.nullable_value, state);
                try self.analyzeNode(unwrap.fallback_value, state);
            },
            .testing_expect_error => |expectation| {
                try self.analyzeNode(expectation.expected_reason, state);
                try self.analyzeNode(expectation.actual_result, state);
            },
            .error_propagation => |propagation| {
                try self.analyzeNode(propagation.errable_value, state);
                for (propagation.cleanup_nodes) |cleanup| try self.analyzeNode(cleanup, state);
            },
            .error_context => |context| {
                try self.analyzeNode(context.errable_value, state);
                try self.analyzeNode(context.context, state);
                for (context.cleanup_nodes) |cleanup| try self.analyzeNode(cleanup, state);
            },
            .explicit_cast => |cast| try self.analyzeNode(cast.value, state),
            .type_initializer => |initializer| try self.analyzeNode(initializer.args, state),
            .auto_deinit_binding,
            .break_statement,
            .continue_statement,
            .choice_option_declaration,
            .type_declaration,
            .function_declaration,
            .test_declaration,
            .reach_directive,
            .value_literal,
            .type_literal,
            => {},
        }
    }

    fn analyzeIf(self: *MemorySafetyAnalyzer, statement: *const sg.IfStatement, state: *FunctionState) !void {
        try self.analyzeNode(statement.condition, state);

        var then_state = try state.clone(self.allocator.*);
        defer then_state.deinit();
        try self.analyzeCodeBlock(statement.then_block, &then_state);

        var else_state = try state.clone(self.allocator.*);
        defer else_state.deinit();
        if (statement.else_block) |else_block| try self.analyzeCodeBlock(else_block, &else_state);

        const merged = try self.mergeStates(&then_state, &else_state);
        state.deinit();
        state.* = merged;
    }

    fn analyzeWhile(self: *MemorySafetyAnalyzer, statement: *const sg.WhileStatement, state: *FunctionState) !void {
        try self.analyzeNode(statement.condition, state);

        var one_iteration = try state.clone(self.allocator.*);
        defer one_iteration.deinit();
        try self.analyzeCodeBlock(statement.body, &one_iteration);

        var merged = try self.mergeStates(state, &one_iteration);
        errdefer merged.deinit();

        // A second iteration exposes uses made stale by the preceding one.
        var next_iteration = try merged.clone(self.allocator.*);
        defer next_iteration.deinit();
        try self.analyzeNode(statement.condition, &next_iteration);
        try self.analyzeCodeBlock(statement.body, &next_iteration);

        const fixed_point = try self.mergeStates(&merged, &next_iteration);
        merged.deinit();
        state.deinit();
        state.* = fixed_point;
    }

    fn analyzeFor(self: *MemorySafetyAnalyzer, statement: *const sg.ForStatement, state: *FunctionState) !void {
        if (statement.init) |initializer| try self.analyzeNode(initializer, state);
        try self.analyzeNode(statement.condition, state);

        var one_iteration = try state.clone(self.allocator.*);
        defer one_iteration.deinit();
        try self.analyzeCodeBlock(statement.body, &one_iteration);
        if (statement.increment) |increment| try self.analyzeNode(increment, &one_iteration);

        var merged = try self.mergeStates(state, &one_iteration);
        errdefer merged.deinit();
        var next_iteration = try merged.clone(self.allocator.*);
        defer next_iteration.deinit();
        try self.analyzeNode(statement.condition, &next_iteration);
        try self.analyzeCodeBlock(statement.body, &next_iteration);
        if (statement.increment) |increment| try self.analyzeNode(increment, &next_iteration);

        const fixed_point = try self.mergeStates(&merged, &next_iteration);
        merged.deinit();
        state.deinit();
        state.* = fixed_point;
    }

    fn analyzeSwitch(self: *MemorySafetyAnalyzer, statement: *const sg.SwitchStatement, state: *FunctionState) !void {
        try self.analyzeNode(statement.expression, state);
        var merged = try state.clone(self.allocator.*);
        errdefer merged.deinit();

        for (statement.cases) |case| {
            var branch = try state.clone(self.allocator.*);
            defer branch.deinit();
            try self.analyzeNode(case.value, &branch);
            try self.analyzeCodeBlock(case.body, &branch);

            const next_merged = try self.mergeStates(&merged, &branch);
            merged.deinit();
            merged = next_merged;
        }
        if (statement.default_case) |default_case| {
            var branch = try state.clone(self.allocator.*);
            defer branch.deinit();
            try self.analyzeCodeBlock(default_case, &branch);

            const next_merged = try self.mergeStates(&merged, &branch);
            merged.deinit();
            merged = next_merged;
        }

        state.deinit();
        state.* = merged;
    }

    fn mergeStates(
        self: *MemorySafetyAnalyzer,
        left: *const FunctionState,
        right: *const FunctionState,
    ) !FunctionState {
        var merged = try left.clone(self.allocator.*);
        errdefer merged.deinit();

        for (right.invalidations.items) |invalidation| {
            var found = false;
            for (merged.invalidations.items) |existing| {
                if (existing.sequence == invalidation.sequence) {
                    found = true;
                    break;
                }
            }
            if (!found) try merged.invalidations.append(invalidation);
        }

        var reference_it = right.references.iterator();
        while (reference_it.next()) |entry| {
            if (merged.references.get(entry.key_ptr.*)) |left_fact| {
                const combined = try self.mergeReferenceFacts(left_fact, entry.value_ptr.*);
                try merged.references.put(entry.key_ptr.*, combined);
            } else {
                try merged.references.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
        return merged;
    }

    fn mergeReferenceFacts(self: *MemorySafetyAnalyzer, left: ReferenceFact, right: ReferenceFact) !ReferenceFact {
        var captured = std.array_list.Managed(CapturedPlace).init(self.allocator.*);
        defer captured.deinit();
        try captured.appendSlice(left.captured);

        for (right.captured) |candidate| {
            var found = false;
            for (captured.items) |existing| {
                if (candidate.capture_sequence == existing.capture_sequence and
                    temporal_place.Place.eql(candidate.place, existing.place) and
                    valuePathsEqual(candidate.value_path, existing.value_path))
                {
                    found = true;
                    break;
                }
            }
            if (!found) try captured.append(candidate);
        }
        return .{ .captured = try captured.toOwnedSlice() };
    }

    fn updateReferenceFact(
        self: *MemorySafetyAnalyzer,
        binding: *const sg.BindingDeclaration,
        value: *const sg.SGNode,
        state: *FunctionState,
    ) !void {
        if (try self.referenceFactFromValue(value, state)) |fact| {
            try state.references.put(binding, fact);
        } else {
            _ = state.references.remove(binding);
        }
    }

    fn updateStoredFieldFact(
        self: *MemorySafetyAnalyzer,
        binding: *const sg.BindingDeclaration,
        field_index: u32,
        value: *const sg.SGNode,
        state: *FunctionState,
    ) !void {
        var captured = std.array_list.Managed(CapturedPlace).init(self.allocator.*);
        defer captured.deinit();
        if (state.references.get(binding)) |existing| {
            for (existing.captured) |dependency| {
                if (dependency.value_path.len > 0 and dependency.value_path[0] == .field and
                    dependency.value_path[0].field == field_index) continue;
                try captured.append(dependency);
            }
        }
        if (try self.factFromProjectedValue(value, .{ .field = field_index }, state)) |replacement| {
            try captured.appendSlice(replacement.captured);
        }
        if (captured.items.len == 0) {
            _ = state.references.remove(binding);
        } else {
            try state.references.put(binding, .{ .captured = try captured.toOwnedSlice() });
        }
    }

    fn validateMoveRelocation(
        self: *MemorySafetyAnalyzer,
        inner: *const sg.SGNode,
        move_node: *const sg.SGNode,
        state: *const FunctionState,
    ) !void {
        if (self.inferring_summaries or inner.content != .binding_use) return;
        const binding = inner.content.binding_use;
        const fact = state.references.get(binding) orelse return;
        for (fact.captured) |dependency| {
            if (dependency.place.root != binding) continue;
            try self.diags.add(
                move_node.location,
                .semantic,
                "cannot relocate address-dependent value '{s}'; transfer it into local backing storage or construct the destination in place",
                .{binding.name},
            );
            return;
        }
    }

    fn referenceFactFromValue(
        self: *MemorySafetyAnalyzer,
        value: *const sg.SGNode,
        state: *const FunctionState,
    ) anyerror!?ReferenceFact {
        if (value.sem_type) |value_type| {
            if (!typ.typeMayCarryTemporalDependencies(value_type)) return null;
        }
        return switch (value.content) {
            .address_of => |target| blk: {
                const place = try temporal_place.Place.fromNode(target, self.allocator) orelse break :blk null;
                const captured = try self.allocator.alloc(CapturedPlace, 1);
                captured[0] = .{
                    .place = place,
                    .capture_sequence = self.next_sequence - 1,
                };
                break :blk .{ .captured = captured };
            },
            .binding_use => |binding| state.references.get(binding),
            .move_value => |inner| try self.referenceFactFromValue(inner, state),
            .struct_value_literal => |struct_value| try self.factFromStructValue(struct_value, state),
            .array_literal => |array_value| try self.factFromNodeList(array_value.elements, state),
            .list_literal => |list_value| try self.factFromNodeList(list_value.elements, state),
            .choice_literal => |choice_value| if (choice_value.payload) |payload|
                try self.factFromProjectedValue(payload, .{ .choice_payload = choice_value.variant_index }, state)
            else
                null,
            .struct_field_access => |access| try self.factFromSelectedValue(
                access.struct_value,
                .{ .field = access.field_index },
                state,
            ),
            .choice_payload_access => |access| try self.factFromSelectedValue(
                access.choice_value,
                .{ .choice_payload = access.variant_index },
                state,
            ),
            .array_index => |access| try self.factFromSelectedValue(
                access.array_ptr,
                .{ .array_index = constantIndex(access.index) },
                state,
            ),
            .dereference => |access| try self.referenceFactFromValue(access.pointer, state),
            .function_call => |call| try self.factFromCall(call, state),
            else => null,
        };
    }

    fn factFromStructValue(
        self: *MemorySafetyAnalyzer,
        value: *const sg.StructValueLiteral,
        state: *const FunctionState,
    ) anyerror!?ReferenceFact {
        var captured = std.array_list.Managed(CapturedPlace).init(self.allocator.*);
        defer captured.deinit();
        for (value.fields, 0..) |field, index| {
            if (try self.factFromProjectedValue(field.value, .{ .field = @intCast(index) }, state)) |fact| {
                try captured.appendSlice(fact.captured);
            }
        }
        if (captured.items.len == 0) return null;
        return .{ .captured = try captured.toOwnedSlice() };
    }

    fn factFromNodeList(
        self: *MemorySafetyAnalyzer,
        values: []const *const sg.SGNode,
        state: *const FunctionState,
    ) anyerror!?ReferenceFact {
        var captured = std.array_list.Managed(CapturedPlace).init(self.allocator.*);
        defer captured.deinit();
        for (values, 0..) |value, index| {
            if (try self.factFromProjectedValue(value, .{ .array_index = @intCast(index) }, state)) |fact| {
                try captured.appendSlice(fact.captured);
            }
        }
        if (captured.items.len == 0) return null;
        return .{ .captured = try captured.toOwnedSlice() };
    }

    fn factFromProjectedValue(
        self: *MemorySafetyAnalyzer,
        value: *const sg.SGNode,
        projection: temporal_place.Projection,
        state: *const FunctionState,
    ) anyerror!?ReferenceFact {
        const fact = try self.referenceFactFromValue(value, state) orelse return null;
        const captured = try self.allocator.alloc(CapturedPlace, fact.captured.len);
        for (fact.captured, 0..) |dependency, index| {
            const value_path = try self.allocator.alloc(temporal_place.Projection, dependency.value_path.len + 1);
            value_path[0] = projection;
            @memcpy(value_path[1..], dependency.value_path);
            captured[index] = dependency;
            captured[index].value_path = value_path;
        }
        return .{ .captured = captured };
    }

    fn factFromSelectedValue(
        self: *MemorySafetyAnalyzer,
        raw_container: *const sg.SGNode,
        projection: temporal_place.Projection,
        state: *const FunctionState,
    ) anyerror!?ReferenceFact {
        if (raw_container.content == .dereference) {
            const pointer_fact = try self.referenceFactFromValue(raw_container.content.dereference.pointer, state) orelse return null;
            const captured = try self.allocator.alloc(CapturedPlace, pointer_fact.captured.len);
            for (pointer_fact.captured, 0..) |dependency, index| {
                captured[index] = dependency;
                captured[index].place = try temporal_place.Place.withProjection(dependency.place, projection, self.allocator);
                captured[index].capture_sequence = self.next_sequence - 1;
            }
            return .{ .captured = captured };
        }
        const container = if (raw_container.content == .address_of)
            raw_container.content.address_of
        else
            raw_container;
        const fact = try self.referenceFactFromValue(container, state) orelse return null;
        var captured = std.array_list.Managed(CapturedPlace).init(self.allocator.*);
        defer captured.deinit();

        for (fact.captured) |dependency| {
            if (dependency.value_path.len == 0) {
                try captured.append(dependency);
                continue;
            }
            if (!valueProjectionsMatch(dependency.value_path[0], projection)) continue;
            var selected = dependency;
            selected.value_path = try self.allocator.dupe(temporal_place.Projection, dependency.value_path[1..]);
            try captured.append(selected);
        }
        if (captured.items.len == 0) return null;
        return .{ .captured = try captured.toOwnedSlice() };
    }

    fn factFromCall(
        self: *MemorySafetyAnalyzer,
        call: *const sg.FunctionCall,
        state: *const FunctionState,
    ) anyerror!?ReferenceFact {
        _ = try self.inferFunctionSummaryPass(call.callee);
        const summary = call.callee.temporal_summary orelse return null;
        if (call.input.content != .struct_value_literal) return null;
        const fields = call.input.content.struct_value_literal.fields;
        var captured = std.array_list.Managed(CapturedPlace).init(self.allocator.*);
        defer captured.deinit();

        for (summary.return_dependencies) |dependency| {
            if (dependency.input_index >= fields.len) continue;
            const actual_fact = try self.referenceFactFromValue(fields[dependency.input_index].value, state) orelse continue;
            for (actual_fact.captured) |actual| {
                var mapped = actual;
                mapped.place = try appendSummaryPath(actual.place, dependency.input_path, self.allocator);
                mapped.value_path = try temporalPathToPlacePath(dependency.output_path, self.allocator);
                try captured.append(mapped);
            }
        }
        for (summary.return_roots) |root| {
            const place = switch (root.source) {
                .fresh => try self.freshStoragePlace(call),
                .input => |source| blk: {
                    if (source.index >= fields.len) continue;
                    const actual_fact = try self.referenceFactFromValue(fields[source.index].value, state) orelse continue;
                    if (actual_fact.captured.len == 0) continue;
                    break :blk try appendSummaryPath(actual_fact.captured[0].place, source.path, self.allocator);
                },
            };
            try captured.append(.{
                .place = place,
                .capture_sequence = self.next_sequence - 1,
                .value_path = try temporalPathToPlacePath(root.output_path, self.allocator),
            });
        }
        if (captured.items.len == 0) return null;
        return .{ .captured = try captured.toOwnedSlice() };
    }

    fn freshStoragePlace(self: *MemorySafetyAnalyzer, call: *const sg.FunctionCall) !temporal_place.Place {
        if (self.fresh_storage_roots.get(call)) |root| return .{ .root = root, .projections = &.{} };
        const root = try self.allocator.create(sg.BindingDeclaration);
        root.* = .{
            .name = "$fresh allocation",
            .location = call.callee.location,
            .origin_file = call.callee.location.file,
            .mutability = .constant,
            .ty = .{ .builtin = .Any },
            .initialization = null,
        };
        try self.fresh_storage_roots.put(call, root);
        return .{ .root = root, .projections = &.{} };
    }

    fn valueProjectionsMatch(left: temporal_place.Projection, right: temporal_place.Projection) bool {
        return switch (left) {
            .field => |left_index| switch (right) {
                .field => |right_index| left_index == right_index,
                else => false,
            },
            .choice_payload => |left_index| switch (right) {
                .choice_payload => |right_index| left_index == right_index,
                else => false,
            },
            .array_index => |left_index| switch (right) {
                .array_index => |right_index| left_index == null or right_index == null or left_index.? == right_index.?,
                else => false,
            },
            .dereference => switch (right) {
                .dereference => true,
                else => false,
            },
        };
    }

    fn validateReferenceUse(
        self: *MemorySafetyAnalyzer,
        binding: *const sg.BindingDeclaration,
        use_node: *const sg.SGNode,
        state: *const FunctionState,
    ) !void {
        const fact = state.references.get(binding) orelse return;
        try self.validateFact(binding.name, fact, use_node, state);
    }

    fn validateExpressionUse(
        self: *MemorySafetyAnalyzer,
        value: *const sg.SGNode,
        state: *const FunctionState,
    ) !void {
        const fact = try self.referenceFactFromValue(value, state) orelse return;
        const label = (try temporal_place.Place.fromNode(value, self.allocator)) orelse return;
        try self.validateFact(label.root.name, fact, value, state);
    }

    fn validateFact(
        self: *MemorySafetyAnalyzer,
        label: []const u8,
        fact: ReferenceFact,
        use_node: *const sg.SGNode,
        state: *const FunctionState,
    ) !void {
        if (self.inferring_summaries) return;
        for (fact.captured) |captured| {
            for (state.invalidations.items) |invalidation| {
                if (invalidation.sequence <= captured.capture_sequence) continue;
                if (!temporal_place.Place.isInvalidatedBy(captured.place, invalidation.place)) continue;
                if (self.reported_uses.contains(use_node)) return;
                const captured_text = try self.formatPlace(captured.place);
                const invalidated_text = try self.formatPlace(invalidation.place);
                try self.diags.add(
                    use_node.location,
                    .semantic,
                    "reference '{s}' is no longer valid; it refers to '{s}' at place '{s}', which was invalidated as '{s}' at {s}:{d}:{d}",
                    .{
                        label,
                        captured.place.root.name,
                        captured_text,
                        invalidated_text,
                        invalidation.location.file,
                        invalidation.location.line,
                        invalidation.location.column,
                    },
                );
                try self.reported_uses.put(use_node, {});
                return;
            }
        }
    }

    fn formatPlace(self: *MemorySafetyAnalyzer, place: temporal_place.Place) ![]const u8 {
        var text = try std.fmt.allocPrint(self.allocator.*, "{s}", .{place.root.name});
        var current_type = place.root.ty;
        for (place.projections) |projection| switch (projection) {
            .dereference => {
                if (current_type == .pointer_type) current_type = current_type.pointer_type.child.*;
            },
            .field => |field_index| {
                if (current_type == .pointer_type) current_type = current_type.pointer_type.child.*;
                if (current_type == .struct_type and field_index < current_type.struct_type.fields.len) {
                    const field = current_type.struct_type.fields[field_index];
                    text = try std.fmt.allocPrint(self.allocator.*, "{s}.{s}", .{ text, field.name });
                    current_type = typ.effectiveStructFieldType(field);
                } else {
                    text = try std.fmt.allocPrint(self.allocator.*, "{s}.#{d}", .{ text, field_index });
                }
            },
            .choice_payload => |variant_index| {
                if (current_type == .choice_type and variant_index < current_type.choice_type.variants.len) {
                    const variant = current_type.choice_type.variants[variant_index];
                    text = try std.fmt.allocPrint(self.allocator.*, "{s}..{s}", .{ text, variant.name });
                    if (variant.payload_type) |payload_type| current_type = payload_type;
                } else {
                    text = try std.fmt.allocPrint(self.allocator.*, "{s}..#{d}", .{ text, variant_index });
                }
            },
            .array_index => |index| {
                text = if (index) |known|
                    try std.fmt.allocPrint(self.allocator.*, "{s}[{d}]", .{ text, known })
                else
                    try std.fmt.allocPrint(self.allocator.*, "{s}[*]", .{text});
                if (current_type == .array_type) current_type = current_type.array_type.element_type.*;
            },
        };
        return text;
    }

    /// Until a precise summary is available, an exclusive parameter may
    /// transition any identity inside its argument envelope. Mutable and
    /// read-only parameters never imply invalidation merely by being called.
    fn recordConservativeCallInvalidations(
        self: *MemorySafetyAnalyzer,
        call: *const sg.FunctionCall,
        call_node: *const sg.SGNode,
        state: *FunctionState,
    ) !void {
        if (call.input.content != .struct_value_literal) return;

        const input = call.input.content.struct_value_literal;
        _ = try self.inferFunctionSummaryPass(call.callee);
        if (call.callee.temporal_summary) |summary| {
            for (summary.invalidations) |invalidation| {
                if (invalidation.input_index >= input.fields.len) continue;
                const actual = input.fields[invalidation.input_index].value;
                const actual_fact = try self.referenceFactFromValue(actual, state) orelse continue;
                for (actual_fact.captured) |captured| {
                    const place = try appendSummaryPath(captured.place, invalidation.input_path, self.allocator);
                    try self.recordInvalidation(place, call_node.location, state);
                }
            }
            return;
        }

        for (input.fields, 0..) |field, index| {
            if (index >= call.callee.input.fields.len) break;
            const parameter = call.callee.input.fields[index];
            if (parameter.ty != .pointer_type or parameter.ty.pointer_type.mutability != .exclusive) continue;
            if (field.value.content != .address_of) continue;
            const place = try temporal_place.Place.fromNode(field.value.content.address_of, self.allocator) orelse continue;
            try self.recordInvalidation(place, call_node.location, state);
        }
    }

    fn seedInputDependencies(
        self: *MemorySafetyAnalyzer,
        function: *const sg.FunctionDeclaration,
        state: *FunctionState,
    ) !void {
        for (function.input_bindings, 0..) |binding, index| {
            if (index >= function.input.fields.len) break;
            if (function.input.fields[index].ty != .pointer_type) continue;
            const captured = try self.allocator.alloc(CapturedPlace, 1);
            captured[0] = .{
                .place = .{ .root = binding, .projections = &.{} },
                .capture_sequence = self.next_sequence - 1,
            };
            try state.references.put(binding, .{ .captured = captured });
        }
    }

    fn inferTemporalSummary(
        self: *MemorySafetyAnalyzer,
        function: *const sg.FunctionDeclaration,
        state: *const FunctionState,
    ) !void {
        var return_dependencies = std.array_list.Managed(sg.ReturnDependency).init(self.allocator.*);
        defer return_dependencies.deinit();
        for (function.output_bindings, 0..) |binding, output_index| {
            const fact = state.references.get(binding) orelse continue;
            for (fact.captured) |captured| {
                const input_index = inputBindingIndex(function, captured.place.root) orelse continue;
                const output_path = try self.allocator.alloc(sg.TemporalProjection, captured.value_path.len + 1);
                output_path[0] = .{ .field = @intCast(output_index) };
                for (captured.value_path, 0..) |projection, index| output_path[index + 1] = toSummaryProjection(projection);
                try return_dependencies.append(.{
                    .output_path = output_path,
                    .input_index = @intCast(input_index),
                    .input_path = try normalizedSummaryPath(captured.place.projections, self.allocator),
                });
            }
        }

        var invalidations = std.array_list.Managed(sg.InvalidationFootprint).init(self.allocator.*);
        defer invalidations.deinit();
        const invalidates_envelope = std.mem.eql(u8, function.name, "deinit") or
            (std.mem.eql(u8, function.name, "reset") and std.mem.indexOf(u8, function.location.file, "/ArenaAllocator.rg") != null);
        if (invalidates_envelope) {
            for (function.input.fields, 0..) |field, input_index| {
                if (field.ty == .pointer_type and field.ty.pointer_type.mutability == .exclusive) {
                    try invalidations.append(.{
                        .input_index = @intCast(input_index),
                        .input_path = &.{},
                    });
                }
            }
        }
        for (state.invalidations.items) |invalidation| {
            const input_index = inputBindingIndex(function, invalidation.place.root) orelse continue;
            try invalidations.append(.{
                .input_index = @intCast(input_index),
                .input_path = try normalizedSummaryPath(invalidation.place.projections, self.allocator),
            });
        }

        const summary = try self.allocator.create(sg.TemporalSummary);
        var return_roots: []const sg.ReturnStorageRoot = &.{};
        if (std.mem.eql(u8, function.name, "allocate") and
            std.mem.indexOf(u8, function.location.file, "/core/memory/heap_allocation/") != null)
        {
            const roots = try self.allocator.alloc(sg.ReturnStorageRoot, 1);
            roots[0] = .{
                .output_path = &.{},
                .source = if (std.mem.indexOf(u8, function.location.file, "/ArenaAllocator.rg") != null)
                    .{ .input = .{ .index = 0, .path = &.{} } }
                else
                    .fresh,
            };
            return_roots = roots;
        }
        summary.* = .{
            .return_dependencies = try return_dependencies.toOwnedSlice(),
            .invalidations = try invalidations.toOwnedSlice(),
            .return_roots = return_roots,
        };
        @constCast(function).temporal_summary = summary;
    }

    fn inputBindingIndex(function: *const sg.FunctionDeclaration, binding: *const sg.BindingDeclaration) ?usize {
        for (function.input_bindings, 0..) |candidate, index| {
            if (candidate == binding) return index;
        }
        return null;
    }

    fn fieldCopiesSameReferentField(
        value: *const sg.SGNode,
        pointer: *const sg.SGNode,
        field_index: u32,
    ) bool {
        if (value.content != .struct_field_access) return false;
        const access = value.content.struct_field_access;
        if (access.field_index != field_index or access.struct_value.content != .dereference) return false;
        return nodesReferToSameValue(access.struct_value.content.dereference.pointer, pointer, 0);
    }

    fn nodesReferToSameValue(left: *const sg.SGNode, right: *const sg.SGNode, depth: usize) bool {
        if (depth >= 24) return false;
        if (left == right) return true;
        return switch (left.content) {
            .binding_use => |left_binding| switch (right.content) {
                .binding_use => |right_binding| left_binding == right_binding or
                    (left_binding.initialization != null and nodesReferToSameValue(left_binding.initialization.?, right, depth + 1)) or
                    (right_binding.initialization != null and nodesReferToSameValue(left, right_binding.initialization.?, depth + 1)),
                else => left_binding.initialization != null and
                    nodesReferToSameValue(left_binding.initialization.?, right, depth + 1),
            },
            else => switch (right.content) {
                .binding_use => |right_binding| right_binding.initialization != null and
                    nodesReferToSameValue(left, right_binding.initialization.?, depth + 1),
                else => false,
            },
        };
    }

    fn recordInvalidation(
        self: *MemorySafetyAnalyzer,
        place: temporal_place.Place,
        location: @import("../2_tokens/token.zig").Location,
        state: *FunctionState,
    ) !void {
        try state.invalidations.append(.{
            .place = place,
            .location = location,
            .sequence = self.next_sequence,
        });
        self.next_sequence += 1;
    }

    fn constantIndex(node: *const sg.SGNode) ?i64 {
        if (node.content != .value_literal) return null;
        if (node.content.value_literal != .int_literal) return null;
        return node.content.value_literal.int_literal;
    }

    fn valuePathsEqual(
        left: []const temporal_place.Projection,
        right: []const temporal_place.Projection,
    ) bool {
        if (left.len != right.len) return false;
        for (left, right) |left_projection, right_projection| {
            if (!std.meta.eql(left_projection, right_projection)) return false;
        }
        return true;
    }

    fn toSummaryProjection(projection: temporal_place.Projection) sg.TemporalProjection {
        return switch (projection) {
            .field => |index| .{ .field = index },
            .choice_payload => |index| .{ .choice_payload = index },
            .array_index => |index| .{ .array_index = index },
            .dereference => .dereference,
        };
    }

    fn toPlaceProjection(projection: sg.TemporalProjection) temporal_place.Projection {
        return switch (projection) {
            .field => |index| .{ .field = index },
            .choice_payload => |index| .{ .choice_payload = index },
            .array_index => |index| .{ .array_index = index },
            .dereference => .dereference,
        };
    }

    fn normalizedSummaryPath(
        projections: []const temporal_place.Projection,
        allocator: *const std.mem.Allocator,
    ) ![]const sg.TemporalProjection {
        const start: usize = if (projections.len > 0 and projections[0] == .dereference) 1 else 0;
        const result = try allocator.alloc(sg.TemporalProjection, projections.len - start);
        for (projections[start..], 0..) |projection, index| result[index] = toSummaryProjection(projection);
        return result;
    }

    fn temporalPathToPlacePath(
        projections: []const sg.TemporalProjection,
        allocator: *const std.mem.Allocator,
    ) ![]const temporal_place.Projection {
        const result = try allocator.alloc(temporal_place.Projection, projections.len);
        for (projections, 0..) |projection, index| result[index] = toPlaceProjection(projection);
        return result;
    }

    fn appendSummaryPath(
        base: temporal_place.Place,
        projections: []const sg.TemporalProjection,
        allocator: *const std.mem.Allocator,
    ) !temporal_place.Place {
        const combined = try allocator.alloc(temporal_place.Projection, base.projections.len + projections.len);
        @memcpy(combined[0..base.projections.len], base.projections);
        for (projections, 0..) |projection, index| combined[base.projections.len + index] = toPlaceProjection(projection);
        return .{ .root = base.root, .projections = combined };
    }

    fn temporalSummariesEqual(left: ?*const sg.TemporalSummary, right: ?*const sg.TemporalSummary) bool {
        if (left == null or right == null) return left == right;
        if (left.?.return_dependencies.len != right.?.return_dependencies.len or
            left.?.invalidations.len != right.?.invalidations.len or
            left.?.return_roots.len != right.?.return_roots.len) return false;
        for (left.?.return_dependencies, right.?.return_dependencies) |a, b| {
            if (a.input_index != b.input_index or !summaryPathsEqual(a.output_path, b.output_path) or
                !summaryPathsEqual(a.input_path, b.input_path)) return false;
        }
        for (left.?.invalidations, right.?.invalidations) |a, b| {
            if (a.input_index != b.input_index or !summaryPathsEqual(a.input_path, b.input_path)) return false;
        }
        for (left.?.return_roots, right.?.return_roots) |a, b| {
            if (!summaryPathsEqual(a.output_path, b.output_path)) return false;
            switch (a.source) {
                .fresh => if (b.source != .fresh) return false,
                .input => |a_input| switch (b.source) {
                    .fresh => return false,
                    .input => |b_input| if (a_input.index != b_input.index or
                        !summaryPathsEqual(a_input.path, b_input.path)) return false,
                },
            }
        }
        return true;
    }

    fn summaryPathsEqual(left: []const sg.TemporalProjection, right: []const sg.TemporalProjection) bool {
        if (left.len != right.len) return false;
        for (left, right) |a, b| if (!std.meta.eql(a, b)) return false;
        return true;
    }
};
