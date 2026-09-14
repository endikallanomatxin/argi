const std = @import("std");
const graph_mod = @import("../global/graph.zig");
const types = @import("../global/types.zig");
const primitives = @import("../primitives/schema.zig");
const facts = @import("facts.zig");
const summaries = @import("summaries.zig");
const value_state = @import("../value_state.zig");

/// Symbolic SafetySummary inference over the compact GlobalSG.
///
/// This is the indexed counterpart of the old checker's `inferBlock` /
/// `inferExpression` layer. Runtime validation must not be used to discover
/// recursive effects: this pass describes outputs in terms of function inputs
/// and lets `summaries.Engine` iterate callers/SCCs to a fixed point.
pub const Infer = struct {
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,
    engine: *summaries.Engine,
    bindings: std.AutoHashMap(graph_mod.GlobalBindingId, facts.ValueEffect),
    place_bindings: std.AutoHashMap(graph_mod.GlobalBindingId, []const facts.InputPath),

    pub fn init(
        allocator: std.mem.Allocator,
        graph: *const graph_mod.GlobalSemanticGraph,
        engine: *summaries.Engine,
    ) Infer {
        return .{
            .allocator = allocator,
            .graph = graph,
            .engine = engine,
            .bindings = std.AutoHashMap(graph_mod.GlobalBindingId, facts.ValueEffect).init(allocator),
            .place_bindings = std.AutoHashMap(graph_mod.GlobalBindingId, []const facts.InputPath).init(allocator),
        };
    }

    pub fn deinit(self: *Infer) void {
        self.bindings.deinit();
        self.place_bindings.deinit();
    }

    /// Establish one empty approximation per function and iterate output effects
    /// until all reverse dependencies are stable. The other SafetySummary
    /// dimensions are deliberately preserved so required-live/post-state/opaque
    /// inference can be layered on this same engine without changing its model.
    pub fn inferOutputFixedPoint(self: *Infer) !void {
        var functions = std.array_list.Managed(graph_mod.GlobalFunctionId).init(self.allocator);
        defer functions.deinit();

        for (self.graph.functions.items, 0..) |function, raw| {
            const id: graph_mod.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            const outputs = try self.allocator.alloc(facts.ValueEffect, function.output_bindings.len);
            @memset(outputs, .{});
            if (!self.engine.summaries.contains(id))
                try self.engine.summaries.put(id, .{ .outputs = outputs });
            try functions.append(id);
        }
        try self.engine.seed(functions.items);

        while (self.engine.nextDirty()) |function| {
            self.engine.beginInference(function);
            const next = self.inferFunction(function) catch |err| {
                self.engine.current = null;
                return err;
            };
            try self.engine.endInference();
            _ = try self.engine.updateSummary(function, next);
        }
    }

    fn inferFunction(self: *Infer, function_id: graph_mod.GlobalFunctionId) !facts.SafetySummary {
        const function = self.graph.function(function_id);
        const previous = self.engine.summaryFor(function_id) orelse return error.MissingSafetySummary;
        const outputs = try self.allocator.dupe(facts.ValueEffect, previous.outputs);

        // Primitive effects are instantiated at the call site so their fresh
        // identities are call-site stable. Keeping declarations fact-free here
        // also prevents one global primitive root identity leaking across calls.
        if (function.safety_primitive != .none or function.body == null) return .{
            .outputs = outputs,
            .required_live_inputs = previous.required_live_inputs,
            .input_post_states = previous.input_post_states,
            .opaque_storage_effects = previous.opaque_storage_effects,
            .opaque_storage_empties = previous.opaque_storage_empties,
        };

        self.bindings.clearRetainingCapacity();
        self.place_bindings.clearRetainingCapacity();
        try self.inferBlock(function_id, function.body.?, outputs);

        var required_live_inputs = std.array_list.Managed(facts.InputPath).init(self.allocator);
        try self.inferRequiredLiveInputsBlock(function_id, function.body.?, &required_live_inputs);

        var post_flow = InputPostStateFlow.init(self.allocator);
        defer post_flow.deinit();
        var post_exits: ?std.array_list.Managed(facts.PlacePostState) = null;
        defer if (post_exits) |*exits| exits.deinit();
        try self.inferInputPostStates(function_id, function.body.?, &post_flow, &post_exits);
        if (post_flow.reachable) try self.recordInputPostStateExit(&post_exits, &post_flow.states);

        var post_states = if (post_exits) |*exits|
            try self.cloneInputPostStates(exits)
        else
            std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        defer post_states.deinit();

        if (function.flags.is_deinit) {
            const input_fields = self.graph.fields.items[function.input.start..][0..function.input.len];
            for (input_fields, 0..) |input_field, index| {
                if (!std.mem.eql(u8, self.graph.text(input_field.name), "self")) continue;
                const mutable_pointer = switch (self.graph.semanticType(input_field.ty)) {
                    .pointer => |pointer| pointer.mutability == .read_write,
                    else => false,
                };
                if (!mutable_pointer) continue;
                const target = facts.InputPath{ .input_index = @intCast(index) };
                try self.recordInputPostState(
                    &post_states,
                    &.{target},
                    .deinitialized,
                    .{},
                    true,
                    false,
                    false,
                    false,
                );
                break;
            }
        }

        return .{
            .outputs = outputs,
            .required_live_inputs = try required_live_inputs.toOwnedSlice(),
            .input_post_states = try post_states.toOwnedSlice(),
            .opaque_storage_effects = previous.opaque_storage_effects,
            .opaque_storage_empties = previous.opaque_storage_empties,
        };
    }

    fn inferBlock(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        block_id: graph_mod.GlobalBlockId,
        outputs: []facts.ValueEffect,
    ) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            const node = self.graph.node(node_id);
            switch (node.content) {
                .binding_declaration => |binding| {
                    const initialization = self.graph.binding(binding).initialization orelse continue;
                    try self.bindings.put(binding, try self.inferExpression(function_id, initialization));
                    try self.place_bindings.put(binding, try self.inferInputPaths(function_id, initialization));
                },
                .assignment => |assignment| {
                    const effect = try self.inferExpression(function_id, assignment.value);
                    if (self.outputIndex(function_id, assignment.binding)) |output_index| {
                        outputs[output_index] = if (outputs[output_index].variants.len != 0 or effect.variants.len != 0)
                            try self.mergeValueEffects(outputs[output_index], effect)
                        else
                            effect;
                    } else {
                        try self.bindings.put(assignment.binding, effect);
                        try self.place_bindings.put(assignment.binding, try self.inferInputPaths(function_id, assignment.value));
                    }
                },
                .if_statement => |statement| {
                    try self.inferBlock(function_id, statement.then_block, outputs);
                    if (statement.else_block) |child| try self.inferBlock(function_id, child, outputs);
                },
                .while_statement => |statement| try self.inferBlock(function_id, statement.body, outputs),
                .for_statement => |statement| try self.inferBlock(function_id, statement.body, outputs),
                .switch_statement => |switch_id| {
                    const statement = self.graph.switches.items[@intFromEnum(switch_id)];
                    for (self.graph.switch_cases.items[statement.cases.start..][0..statement.cases.len]) |case|
                        try self.inferBlock(function_id, case.body, outputs);
                    if (statement.default_block) |child| try self.inferBlock(function_id, child, outputs);
                },
                .code_block => |child| try self.inferBlock(function_id, child, outputs),
                else => {},
            }
        }
    }

    const SymbolicInputOverride = struct {
        input_index: u32,
        effect: facts.ValueEffect,
    };

    const InputPostStateFlow = struct {
        states: std.array_list.Managed(facts.PlacePostState),
        reachable: bool = true,

        fn init(allocator: std.mem.Allocator) InputPostStateFlow {
            return .{ .states = std.array_list.Managed(facts.PlacePostState).init(allocator) };
        }

        fn deinit(self: *InputPostStateFlow) void {
            self.states.deinit();
        }

        fn clone(self: *const InputPostStateFlow, allocator: std.mem.Allocator) !InputPostStateFlow {
            var states = std.array_list.Managed(facts.PlacePostState).init(allocator);
            try states.appendSlice(self.states.items);
            return .{ .states = states, .reachable = self.reachable };
        }
    };

    fn inferInputPostStates(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        block_id: graph_mod.GlobalBlockId,
        flow: *InputPostStateFlow,
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            if (!flow.reachable) break;
            try self.inferInputPostStatesNode(function_id, node_id, flow, exits);
        }
        if (flow.reachable) if (block.ret_val) |value|
            try self.inferInputPostStatesExpression(function_id, value, &flow.states, exits);
    }

    fn inferInputPostStatesNode(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        flow: *InputPostStateFlow,
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) anyerror!void {
        const node = self.graph.node(node_id);
        const states = &flow.states;
        switch (node.content) {
            .binding_declaration => |binding| {
                if (self.graph.binding(binding).initialization) |initialization|
                    try self.inferInputPostStatesExpression(function_id, initialization, states, exits);
            },
            .assignment => |assignment| try self.inferInputPostStatesExpression(function_id, assignment.value, states, exits),
            .function_call, .virtual_call => try self.inferInputPostStatesExpression(function_id, node_id, states, exits),
            .pointer_assignment => |assignment| {
                try self.inferInputPostStatesExpression(function_id, assignment.pointer, states, exits);
                try self.inferInputPostStatesExpression(function_id, assignment.value, states, exits);
                try self.recordInputPostState(
                    states,
                    try self.inferInputPaths(function_id, assignment.pointer),
                    .initialized,
                    try self.inferExpression(function_id, assignment.value),
                    false,
                    false,
                    false,
                    true,
                );
            },
            .struct_field_store => |store| {
                try self.inferInputPostStatesExpression(function_id, store.struct_ptr, states, exits);
                try self.inferInputPostStatesExpression(function_id, store.value, states, exits);
                const targets = try self.projectInputPaths(
                    try self.inferInputPaths(function_id, store.struct_ptr),
                    .{ .field = store.field_index },
                );
                try self.recordInputPostState(
                    states,
                    targets,
                    .initialized,
                    try self.inferExpression(function_id, store.value),
                    false,
                    false,
                    false,
                    true,
                );
            },
            .array_store => |store| {
                try self.inferInputPostStatesExpression(function_id, store.array_ptr, states, exits);
                try self.inferInputPostStatesExpression(function_id, store.index, states, exits);
                try self.inferInputPostStatesExpression(function_id, store.value, states, exits);
                const projection: facts.Projection = if (self.staticIndex(store.index)) |index|
                    .{ .static_index = index }
                else
                    .dynamic_index;
                const targets = try self.projectInputPaths(
                    try self.inferInputPaths(function_id, store.array_ptr),
                    projection,
                );
                try self.recordInputPostState(
                    states,
                    targets,
                    .initialized,
                    try self.inferExpression(function_id, store.value),
                    false,
                    false,
                    false,
                    true,
                );
            },
            .if_statement => |statement| {
                try self.inferInputPostStatesExpression(function_id, statement.condition, states, exits);
                var then_flow = try flow.clone(self.allocator);
                defer then_flow.deinit();
                try self.inferInputPostStates(function_id, statement.then_block, &then_flow, exits);
                var else_flow = try flow.clone(self.allocator);
                defer else_flow.deinit();
                if (statement.else_block) |child|
                    try self.inferInputPostStates(function_id, child, &else_flow, exits);
                try self.joinInputPostStateFallthrough(flow, &then_flow, &else_flow);
            },
            .while_statement => |statement| {
                try self.inferInputPostStatesExpression(function_id, statement.condition, states, exits);
                var body_flow = try flow.clone(self.allocator);
                defer body_flow.deinit();
                try self.inferInputPostStates(function_id, statement.body, &body_flow, exits);
                try self.joinInputPostStates(states, states, &body_flow.states);
            },
            .for_statement => |statement| {
                if (statement.init) |initialization|
                    try self.inferInputPostStatesNode(function_id, initialization, flow, exits);
                if (!flow.reachable) return;
                try self.inferInputPostStatesExpression(function_id, statement.condition, states, exits);
                var body_flow = try flow.clone(self.allocator);
                defer body_flow.deinit();
                try self.inferInputPostStates(function_id, statement.body, &body_flow, exits);
                if (body_flow.reachable) if (statement.increment) |increment|
                    try self.inferInputPostStatesNode(function_id, increment, &body_flow, exits);
                try self.joinInputPostStates(states, states, &body_flow.states);
            },
            .switch_statement => |switch_id| {
                const statement = self.graph.switches.items[@intFromEnum(switch_id)];
                try self.inferInputPostStatesExpression(function_id, statement.expression, states, exits);
                var joined: ?InputPostStateFlow = null;
                defer if (joined) |*joined_flow| joined_flow.deinit();

                for (self.graph.switch_cases.items[statement.cases.start..][0..statement.cases.len]) |case| {
                    var branch = try flow.clone(self.allocator);
                    defer branch.deinit();
                    try self.inferInputPostStates(function_id, case.body, &branch, exits);
                    try self.joinInputPostStateFlowBranch(&joined, &branch);
                }
                if (statement.default_block) |child| {
                    var branch = try flow.clone(self.allocator);
                    defer branch.deinit();
                    try self.inferInputPostStates(function_id, child, &branch, exits);
                    try self.joinInputPostStateFlowBranch(&joined, &branch);
                } else if (!statement.exhaustive) {
                    try self.joinInputPostStateFlowBranch(&joined, flow);
                }
                if (joined) |*joined_flow|
                    try self.copyInputPostStateFlow(flow, joined_flow)
                else
                    flow.reachable = false;
            },
            .return_statement => |statement| {
                if (statement.expression) |expression|
                    try self.inferInputPostStatesExpression(function_id, expression, states, exits);
                try self.inferInputPostStatesRange(function_id, statement.cleanup, flow, exits);
                if (flow.reachable) try self.recordInputPostStateExit(exits, states);
                flow.reachable = false;
            },
            .code_block => |child| try self.inferInputPostStates(function_id, child, flow, exits),
            .break_statement, .continue_statement => flow.reachable = false,
            .auto_deinit_binding => |auto_id| try self.applyAutoDeinitInputPostStates(function_id, auto_id, states),
            else => try self.inferInputPostStatesExpression(function_id, node_id, states, exits),
        }
    }

    fn inferInputPostStatesRange(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        range: graph_mod.NodeRange,
        flow: *InputPostStateFlow,
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) anyerror!void {
        for (self.graph.node_refs.items[range.start..][0..range.len]) |node| {
            if (!flow.reachable) break;
            try self.inferInputPostStatesNode(function_id, node, flow, exits);
        }
    }

    fn inferInputPostStatesExpression(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        states: *std.array_list.Managed(facts.PlacePostState),
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) anyerror!void {
        const node = self.graph.node(node_id);
        switch (node.content) {
            .move_value, .address_of => |value| try self.inferInputPostStatesExpression(function_id, value, states, exits),
            .dereference => |value| try self.inferInputPostStatesExpression(function_id, value.pointer, states, exits),
            .struct_value_literal => |literal| {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field|
                    try self.inferInputPostStatesExpression(function_id, field.value, states, exits);
            },
            .list_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.inferInputPostStatesExpression(function_id, element, states, exits);
            },
            .array_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.inferInputPostStatesExpression(function_id, element, states, exits);
            },
            .choice_literal => |literal| {
                if (literal.payload) |payload|
                    try self.inferInputPostStatesExpression(function_id, payload, states, exits);
            },
            .struct_field_access => |access| try self.inferInputPostStatesExpression(function_id, access.value, states, exits),
            .choice_payload_access => |access| try self.inferInputPostStatesExpression(function_id, access.value, states, exits),
            .array_index => |index| {
                try self.inferInputPostStatesExpression(function_id, index.array_ptr, states, exits);
                try self.inferInputPostStatesExpression(function_id, index.index, states, exits);
            },
            .explicit_cast => |cast| try self.inferInputPostStatesExpression(function_id, cast.value, states, exits),
            .binary_operation => |operation| {
                try self.inferInputPostStatesExpression(function_id, operation.left, states, exits);
                try self.inferInputPostStatesExpression(function_id, operation.right, states, exits);
            },
            .comparison => |comparison| {
                try self.inferInputPostStatesExpression(function_id, comparison.left, states, exits);
                try self.inferInputPostStatesExpression(function_id, comparison.right, states, exits);
            },
            .logical_operation => |operation| {
                try self.inferInputPostStatesExpression(function_id, operation.left, states, exits);
                try self.inferConditionalInputPostStatesExpression(function_id, operation.right, states, exits);
            },
            .nullable_unwrap_or => |unwrap_id| {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(unwrap_id)];
                try self.inferInputPostStatesExpression(function_id, unwrap.nullable_value, states, exits);
                try self.inferConditionalInputPostStatesExpression(function_id, unwrap.fallback_value, states, exits);
            },
            .testing_expect_error => |expect_id| {
                const expect = self.graph.testing_expect_errors.items[@intFromEnum(expect_id)];
                try self.inferInputPostStatesExpression(function_id, expect.expected_reason, states, exits);
                try self.inferInputPostStatesExpression(function_id, expect.actual_result, states, exits);
            },
            .error_propagation => |propagation_id| {
                const propagation = self.graph.error_propagations.items[@intFromEnum(propagation_id)];
                try self.inferInputPostStatesExpression(function_id, propagation.errable_value, states, exits);
                var error_flow = InputPostStateFlow.init(self.allocator);
                defer error_flow.deinit();
                try error_flow.states.appendSlice(states.items);
                for (self.graph.node_refs.items[propagation.cleanup_nodes.start..][0..propagation.cleanup_nodes.len]) |cleanup| {
                    if (!error_flow.reachable) break;
                    try self.inferInputPostStatesNode(function_id, cleanup, &error_flow, exits);
                }
                if (error_flow.reachable) try self.recordInputPostStateExit(exits, &error_flow.states);
            },
            .error_context => |context_id| {
                const context = self.graph.error_contexts.items[@intFromEnum(context_id)];
                try self.inferInputPostStatesExpression(function_id, context.errable_value, states, exits);
                var error_flow = InputPostStateFlow.init(self.allocator);
                defer error_flow.deinit();
                try error_flow.states.appendSlice(states.items);
                try self.inferInputPostStatesExpression(function_id, context.context, &error_flow.states, exits);
                for (self.graph.node_refs.items[context.cleanup_nodes.start..][0..context.cleanup_nodes.len]) |cleanup| {
                    if (!error_flow.reachable) break;
                    try self.inferInputPostStatesNode(function_id, cleanup, &error_flow, exits);
                }
                if (error_flow.reachable) try self.recordInputPostStateExit(exits, &error_flow.states);
            },
            .function_call => |call| {
                try self.inferInputPostStatesExpression(function_id, call.input, states, exits);
                try self.applyInputPostStatesFromFunctionCall(function_id, call.callee, call.input, states);
            },
            .virtual_call => |virtual_call_id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(virtual_call_id)];
                try self.inferInputPostStatesExpression(function_id, call.handle, states, exits);
                try self.inferInputPostStatesExpression(function_id, call.input, states, exits);
            },
            .virtualize => |virtualize_id| try self.inferInputPostStatesExpression(
                function_id,
                self.graph.virtualizes.items[@intFromEnum(virtualize_id)].value,
                states,
                exits,
            ),
            .type_initializer => |initializer| try self.inferInputPostStatesExpression(function_id, initializer.args, states, exits),
            else => {},
        }
    }

    fn inferConditionalInputPostStatesExpression(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        states: *std.array_list.Managed(facts.PlacePostState),
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) !void {
        var executed = try self.cloneInputPostStates(states);
        defer executed.deinit();
        try self.inferInputPostStatesExpression(function_id, node_id, &executed, exits);
        var skipped = try self.cloneInputPostStates(states);
        defer skipped.deinit();
        try self.joinInputPostStates(states, &executed, &skipped);
    }

    fn applyInputPostStatesFromFunctionCall(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        callee: graph_mod.GlobalFunctionId,
        input: graph_mod.GlobalNodeId,
        states: *std.array_list.Managed(facts.PlacePostState),
    ) !void {
        const arguments = self.structArguments(input) orelse return;
        const callee_function = self.graph.function(callee);
        if (callee_function.safety_primitive == .trusted_opaque_move or
            callee_function.safety_primitive == .trusted_opaque_move_in)
        {
            if (arguments.len >= 2) {
                const source_index: usize = if (arguments.len == 3) 2 else 1;
                const targets = try self.inferInputPaths(function_id, arguments[source_index].value);
                const storage = if (arguments.len == 3) blk: {
                    const storage_targets = try self.inferInputPaths(function_id, arguments[0].value);
                    break :blk if (storage_targets.len == 1) storage_targets[0] else null;
                } else null;
                try self.recordOpaqueOwnershipConsumption(states, targets, .definite, storage);
            }
            return;
        }
        if (callee_function.safety_primitive == .trusted_opaque_relocate) return;
        if (callee_function.safety_primitive == .relocate) {
            if (arguments.len != 2) return;
            const source_targets = try self.inferInputPaths(function_id, arguments[0].value);
            const destination_targets = try self.inferInputPaths(function_id, arguments[1].value);
            for (source_targets) |source| {
                try self.recordInputPostState(states, &.{source}, .moved, .{}, false, false, false, false);
                var transferred = try self.inputValueEffect(source.input_index, source.projections);
                transferred = try self.withOwnershipTransfer(transferred);
                for (destination_targets) |destination|
                    try self.recordInputPostState(
                        states,
                        &.{destination},
                        .initialized,
                        transferred,
                        false,
                        false,
                        true,
                        false,
                    );
            }
            return;
        }
        const summary = self.engine.summaryFor(callee) orelse return;
        try self.applyInputPostStatesFromSummary(function_id, summary, input, states, null);
    }

    fn applyInputPostStatesFromSummary(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        summary: facts.SafetySummary,
        input: graph_mod.GlobalNodeId,
        states: *std.array_list.Managed(facts.PlacePostState),
        override: ?SymbolicInputOverride,
    ) !void {
        const arguments = self.structArguments(input) orelse return;
        for (summary.input_post_states) |post_state| {
            if (post_state.target.input_index >= arguments.len) continue;
            const targets = try self.substituteRequiredInputPath(
                function_id,
                post_state.target,
                arguments,
                override,
            );
            if (post_state.opaque_ownership != .none) {
                const storage = if (post_state.opaque_storage) |opaque_storage| blk: {
                    if (opaque_storage.input_index >= arguments.len) break :blk null;
                    const mapped = try self.substituteRequiredInputPath(
                        function_id,
                        opaque_storage,
                        arguments,
                        override,
                    );
                    break :blk if (mapped.len == 1) mapped[0] else null;
                } else null;
                try self.recordOpaqueOwnershipConsumption(
                    states,
                    targets,
                    post_state.opaque_ownership,
                    storage,
                );
                continue;
            }
            const value = try self.substituteOutputWithOverride(
                function_id,
                post_state.value,
                arguments,
                override,
            );
            try self.recordInputPostState(
                states,
                targets,
                post_state.initializedness,
                value,
                post_state.ends_previous_roots,
                post_state.refreshes_storage_generation,
                post_state.requires_available_destination,
                post_state.may_repopulate_opaque_storage,
            );
        }
    }

    fn applyAutoDeinitInputPostStates(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        auto_id: graph_mod.GlobalAutoDeinitId,
        states: *std.array_list.Managed(facts.PlacePostState),
    ) !void {
        const cleanup = self.graph.auto_deinits.items[@intFromEnum(auto_id)];
        const binding_effect = self.bindings.get(cleanup.binding);
        if (cleanup.deinit_fn) |deinit_fn| if (cleanup.input) |input| {
            if (self.engine.summaryFor(deinit_fn)) |summary|
                try self.applyInputPostStatesFromSummary(
                    function_id,
                    summary,
                    input,
                    states,
                    if (binding_effect) |effect| .{ .input_index = cleanup.self_field_index, .effect = effect } else null,
                );
        };
        if (binding_effect) |effect|
            try self.applyAutoDeinitFieldInputPostStates(function_id, cleanup.fields, states, effect);
    }

    fn applyAutoDeinitFieldInputPostStates(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        field_range: primitives.Range(graph_mod.GlobalAutoDeinitFieldId),
        states: *std.array_list.Managed(facts.PlacePostState),
        parent_effect: facts.ValueEffect,
    ) !void {
        for (self.graph.auto_deinit_fields.items[field_range.start..][0..field_range.len]) |field| {
            const field_effect = try self.projectValueEffect(parent_effect, .{ .field = field.field_index });
            if (field.deinit_fn) |deinit_fn| if (field.input) |input| {
                if (self.engine.summaryFor(deinit_fn)) |summary|
                    try self.applyInputPostStatesFromSummary(
                        function_id,
                        summary,
                        input,
                        states,
                        .{ .input_index = field.self_field_index, .effect = field_effect },
                    );
            };
            try self.applyAutoDeinitFieldInputPostStates(function_id, field.fields, states, field_effect);
        }
    }

    fn recordInputPostState(
        self: *Infer,
        states: *std.array_list.Managed(facts.PlacePostState),
        targets: []const facts.InputPath,
        initializedness: value_state.Initializedness,
        value: facts.ValueEffect,
        ends_roots: bool,
        refreshes_storage_generation: bool,
        requires_available_destination: bool,
        may_repopulate_opaque_storage: bool,
    ) !void {
        for (targets) |target| {
            var existing_state: ?*facts.PlacePostState = null;
            for (states.items) |*existing| if (self.inputPathEqual(existing.target, target)) {
                existing_state = existing;
                break;
            };
            if (existing_state) |existing| {
                const was_deinitialized = existing.initializedness != .initialized;
                existing.initializedness = initializedness;
                existing.value = value;
                existing.ends_previous_roots = existing.ends_previous_roots or ends_roots;
                existing.refreshes_storage_generation =
                    existing.refreshes_storage_generation or
                    refreshes_storage_generation or
                    (was_deinitialized and initializedness == .initialized);
                existing.requires_available_destination =
                    existing.requires_available_destination or requires_available_destination;
                existing.may_repopulate_opaque_storage =
                    existing.may_repopulate_opaque_storage or may_repopulate_opaque_storage;
            } else try states.append(.{
                .target = target,
                .initializedness = initializedness,
                .value = value,
                .ends_previous_roots = ends_roots,
                .refreshes_storage_generation = refreshes_storage_generation,
                .requires_available_destination = requires_available_destination,
                .may_repopulate_opaque_storage = may_repopulate_opaque_storage,
            });
        }
    }

    fn recordOpaqueOwnershipConsumption(
        self: *Infer,
        states: *std.array_list.Managed(facts.PlacePostState),
        targets: []const facts.InputPath,
        consumption: facts.OpaqueOwnershipConsumption,
        storage: ?facts.InputPath,
    ) !void {
        for (targets) |target| {
            var existing_state: ?*facts.PlacePostState = null;
            for (states.items) |*existing| if (self.inputPathEqual(existing.target, target)) {
                existing_state = existing;
                break;
            };
            if (existing_state) |existing| {
                existing.opaque_ownership = consumption;
                existing.opaque_storage = storage;
            } else try states.append(.{
                .target = target,
                .initializedness = .initialized,
                .opaque_ownership = consumption,
                .opaque_storage = storage,
            });
        }
    }

    fn joinInputPostStates(
        self: *Infer,
        destination: *std.array_list.Managed(facts.PlacePostState),
        left: *const std.array_list.Managed(facts.PlacePostState),
        right: *const std.array_list.Managed(facts.PlacePostState),
    ) !void {
        var joined = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        defer joined.deinit();

        for (left.items) |left_state| {
            var merged = left_state;
            if (self.findInputPostState(right.items, left_state.target)) |right_state| {
                merged.initializedness = joinInitializedness(left_state.initializedness, right_state.initializedness);
                merged.value = try self.mergeValueEffects(left_state.value, right_state.value);
                merged.ends_previous_roots = left_state.ends_previous_roots or right_state.ends_previous_roots;
                merged.refreshes_storage_generation =
                    left_state.refreshes_storage_generation or right_state.refreshes_storage_generation;
                merged.requires_available_destination =
                    left_state.requires_available_destination or right_state.requires_available_destination;
                merged.may_repopulate_opaque_storage =
                    left_state.may_repopulate_opaque_storage or right_state.may_repopulate_opaque_storage;
                self.joinOpaqueOwnershipEffect(&merged, left_state, right_state);
            } else {
                if (left_state.initializedness != .initialized) {
                    merged.initializedness = .maybe_initialized;
                } else {
                    merged.value = try self.mergeValueEffects(
                        left_state.value,
                        try self.inputPlaceValueEffect(left_state.target),
                    );
                }
                self.joinOpaqueOwnershipEffect(
                    &merged,
                    left_state,
                    .{ .target = left_state.target, .initializedness = .initialized },
                );
            }
            try joined.append(merged);
        }

        for (right.items) |right_state| {
            if (self.findInputPostState(left.items, right_state.target) != null) continue;
            var merged = right_state;
            if (right_state.initializedness != .initialized) {
                merged.initializedness = .maybe_initialized;
            } else {
                merged.value = try self.mergeValueEffects(
                    right_state.value,
                    try self.inputPlaceValueEffect(right_state.target),
                );
            }
            self.joinOpaqueOwnershipEffect(
                &merged,
                .{ .target = right_state.target, .initializedness = .initialized },
                right_state,
            );
            try joined.append(merged);
        }

        destination.clearRetainingCapacity();
        try destination.appendSlice(joined.items);
    }

    fn joinInputPostStateFallthrough(
        self: *Infer,
        destination: *InputPostStateFlow,
        left: *const InputPostStateFlow,
        right: *const InputPostStateFlow,
    ) !void {
        if (!left.reachable and !right.reachable) {
            destination.states.clearRetainingCapacity();
            destination.reachable = false;
        } else if (!left.reachable) {
            try self.copyInputPostStateFlow(destination, right);
        } else if (!right.reachable) {
            try self.copyInputPostStateFlow(destination, left);
        } else {
            try self.joinInputPostStates(&destination.states, &left.states, &right.states);
            destination.reachable = true;
        }
    }

    fn joinInputPostStateFlowBranch(
        self: *Infer,
        joined: *?InputPostStateFlow,
        branch: *const InputPostStateFlow,
    ) !void {
        if (joined.*) |*current| {
            var combined = InputPostStateFlow.init(self.allocator);
            try self.joinInputPostStateFallthrough(&combined, current, branch);
            current.deinit();
            current.* = combined;
        } else {
            joined.* = try branch.clone(self.allocator);
        }
    }

    fn copyInputPostStateFlow(
        self: *Infer,
        destination: *InputPostStateFlow,
        source: *const InputPostStateFlow,
    ) !void {
        _ = self;
        destination.states.clearRetainingCapacity();
        try destination.states.appendSlice(source.states.items);
        destination.reachable = source.reachable;
    }

    fn recordInputPostStateExit(
        self: *Infer,
        exits: *?std.array_list.Managed(facts.PlacePostState),
        states: *const std.array_list.Managed(facts.PlacePostState),
    ) !void {
        if (exits.*) |*current| {
            var combined = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
            defer combined.deinit();
            try self.joinInputPostStates(&combined, current, states);
            current.clearRetainingCapacity();
            try current.appendSlice(combined.items);
        } else {
            exits.* = try self.cloneInputPostStates(states);
        }
    }

    fn cloneInputPostStates(
        self: *Infer,
        source: *const std.array_list.Managed(facts.PlacePostState),
    ) !std.array_list.Managed(facts.PlacePostState) {
        var result = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        try result.appendSlice(source.items);
        return result;
    }

    fn findInputPostState(
        self: *Infer,
        states: []const facts.PlacePostState,
        target: facts.InputPath,
    ) ?facts.PlacePostState {
        for (states) |state| if (self.inputPathEqual(state.target, target)) return state;
        return null;
    }

    fn inputPathEqual(self: *Infer, left: facts.InputPath, right: facts.InputPath) bool {
        _ = self;
        if (left.input_index != right.input_index or left.projections.len != right.projections.len) return false;
        for (left.projections, right.projections) |a, b| if (!std.meta.eql(a, b)) return false;
        return true;
    }

    fn optionalInputPathEqual(self: *Infer, left: ?facts.InputPath, right: ?facts.InputPath) bool {
        if ((left == null) != (right == null)) return false;
        return if (left) |path| self.inputPathEqual(path, right.?) else true;
    }

    fn joinOpaqueOwnershipEffect(
        self: *Infer,
        merged: *facts.PlacePostState,
        left: facts.PlacePostState,
        right: facts.PlacePostState,
    ) void {
        const left_ownership = left.opaque_ownership;
        const right_ownership = right.opaque_ownership;
        if (left_ownership == .ambiguous or right_ownership == .ambiguous) {
            merged.opaque_ownership = .ambiguous;
            merged.opaque_storage = null;
            return;
        }
        if (left_ownership == .none and right_ownership == .none) {
            merged.opaque_ownership = .none;
            merged.opaque_storage = null;
            return;
        }

        const left_storage = if (left_ownership == .none) right.opaque_storage else left.opaque_storage;
        const right_storage = if (right_ownership == .none) left.opaque_storage else right.opaque_storage;
        if (!self.optionalInputPathEqual(left_storage, right_storage)) {
            merged.opaque_ownership = .ambiguous;
            merged.opaque_storage = null;
            return;
        }

        merged.opaque_storage = left_storage;
        if (left_ownership == .none or right_ownership == .none or
            left_ownership == .conditional or right_ownership == .conditional)
        {
            merged.opaque_ownership = .conditional;
        } else {
            merged.opaque_ownership = .definite;
        }
    }

    fn inputPlaceValueEffect(self: *Infer, target: facts.InputPath) !facts.ValueEffect {
        return .{ .input_place_values = try self.oneInputPath(target.input_index, target.projections) };
    }

    fn inferRequiredLiveInputsBlock(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        block_id: graph_mod.GlobalBlockId,
        required: *std.array_list.Managed(facts.InputPath),
    ) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id|
            try self.inferRequiredLiveInputsNode(function_id, node_id, required);
        if (block.ret_val) |value| try self.inferRequiredLiveInputsNode(function_id, value, required);
    }

    fn inferRequiredLiveInputsNode(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        required: *std.array_list.Managed(facts.InputPath),
    ) anyerror!void {
        const node = self.graph.node(node_id);
        if (pointerUseOperand(node.content)) |pointer|
            try self.recordPointerUseRequirement(function_id, pointer, required);

        switch (node.content) {
            .binding_declaration => |binding| {
                if (self.graph.binding(binding).initialization) |initialization|
                    try self.inferRequiredLiveInputsNode(function_id, initialization, required);
            },
            .assignment => |assignment| try self.inferRequiredLiveInputsNode(function_id, assignment.value, required),
            .move_value, .address_of => |value| try self.inferRequiredLiveInputsNode(function_id, value, required),
            .dereference => |value| try self.inferRequiredLiveInputsNode(function_id, value.pointer, required),
            .array_index => |index| {
                try self.inferRequiredLiveInputsNode(function_id, index.array_ptr, required);
                try self.inferRequiredLiveInputsNode(function_id, index.index, required);
            },
            .array_store => |store| {
                try self.inferRequiredLiveInputsNode(function_id, store.array_ptr, required);
                try self.inferRequiredLiveInputsNode(function_id, store.index, required);
                try self.inferRequiredLiveInputsNode(function_id, store.value, required);
            },
            .pointer_assignment => |assignment| {
                try self.inferRequiredLiveInputsNode(function_id, assignment.pointer, required);
                try self.inferRequiredLiveInputsNode(function_id, assignment.value, required);
            },
            .struct_field_access => |access| try self.inferRequiredLiveInputsNode(function_id, access.value, required),
            .choice_payload_access => |access| try self.inferRequiredLiveInputsNode(function_id, access.value, required),
            .explicit_cast => |cast| try self.inferRequiredLiveInputsNode(function_id, cast.value, required),
            .struct_field_store => |store| {
                try self.inferRequiredLiveInputsNode(function_id, store.struct_ptr, required);
                try self.inferRequiredLiveInputsNode(function_id, store.value, required);
            },
            .struct_value_literal => |literal| {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field|
                    try self.inferRequiredLiveInputsNode(function_id, field.value, required);
            },
            .list_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.inferRequiredLiveInputsNode(function_id, element, required);
            },
            .array_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.inferRequiredLiveInputsNode(function_id, element, required);
            },
            .choice_literal => |literal| {
                if (literal.payload) |payload| try self.inferRequiredLiveInputsNode(function_id, payload, required);
            },
            .function_call => |call| {
                try self.inferRequiredLiveInputsNode(function_id, call.input, required);
                if (self.engine.summaryFor(call.callee)) |summary|
                    try self.substituteRequiredLiveInputs(function_id, summary.required_live_inputs, call.input, required);
            },
            .virtual_call => |virtual_call_id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(virtual_call_id)];
                try self.inferRequiredLiveInputsNode(function_id, call.handle, required);
                try self.inferRequiredLiveInputsNode(function_id, call.input, required);
                // Virtual summary merging is restored separately; traversing
                // both operands here preserves their direct requirements.
            },
            .virtualize => |virtualize_id| try self.inferRequiredLiveInputsNode(
                function_id,
                self.graph.virtualizes.items[@intFromEnum(virtualize_id)].value,
                required,
            ),
            .binary_operation => |operation| {
                try self.inferRequiredLiveInputsNode(function_id, operation.left, required);
                try self.inferRequiredLiveInputsNode(function_id, operation.right, required);
            },
            .comparison => |comparison| {
                try self.inferRequiredLiveInputsNode(function_id, comparison.left, required);
                try self.inferRequiredLiveInputsNode(function_id, comparison.right, required);
            },
            .logical_operation => |operation| {
                try self.inferRequiredLiveInputsNode(function_id, operation.left, required);
                try self.inferRequiredLiveInputsNode(function_id, operation.right, required);
            },
            .nullable_unwrap_or => |unwrap_id| {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(unwrap_id)];
                try self.inferRequiredLiveInputsNode(function_id, unwrap.nullable_value, required);
                try self.inferRequiredLiveInputsNode(function_id, unwrap.fallback_value, required);
            },
            .testing_expect_error => |expect_id| {
                const expect = self.graph.testing_expect_errors.items[@intFromEnum(expect_id)];
                try self.inferRequiredLiveInputsNode(function_id, expect.expected_reason, required);
                try self.inferRequiredLiveInputsNode(function_id, expect.actual_result, required);
            },
            .error_propagation => |propagation_id| {
                const propagation = self.graph.error_propagations.items[@intFromEnum(propagation_id)];
                try self.inferRequiredLiveInputsNode(function_id, propagation.errable_value, required);
                try self.inferRequiredLiveInputsRange(function_id, propagation.cleanup_nodes, required);
            },
            .error_context => |context_id| {
                const context = self.graph.error_contexts.items[@intFromEnum(context_id)];
                try self.inferRequiredLiveInputsNode(function_id, context.errable_value, required);
                try self.inferRequiredLiveInputsNode(function_id, context.context, required);
                try self.inferRequiredLiveInputsRange(function_id, context.cleanup_nodes, required);
            },
            .if_statement => |statement| {
                try self.inferRequiredLiveInputsNode(function_id, statement.condition, required);
                try self.inferRequiredLiveInputsBlock(function_id, statement.then_block, required);
                if (statement.else_block) |child| try self.inferRequiredLiveInputsBlock(function_id, child, required);
            },
            .while_statement => |statement| {
                try self.inferRequiredLiveInputsNode(function_id, statement.condition, required);
                try self.inferRequiredLiveInputsBlock(function_id, statement.body, required);
            },
            .for_statement => |statement| {
                if (statement.init) |initialization| try self.inferRequiredLiveInputsNode(function_id, initialization, required);
                try self.inferRequiredLiveInputsNode(function_id, statement.condition, required);
                if (statement.increment) |increment| try self.inferRequiredLiveInputsNode(function_id, increment, required);
                try self.inferRequiredLiveInputsBlock(function_id, statement.body, required);
            },
            .switch_statement => |switch_id| {
                const statement = self.graph.switches.items[@intFromEnum(switch_id)];
                try self.inferRequiredLiveInputsNode(function_id, statement.expression, required);
                for (self.graph.switch_cases.items[statement.cases.start..][0..statement.cases.len]) |case| {
                    try self.inferRequiredLiveInputsNode(function_id, case.value, required);
                    try self.inferRequiredLiveInputsBlock(function_id, case.body, required);
                }
                if (statement.default_block) |child| try self.inferRequiredLiveInputsBlock(function_id, child, required);
            },
            .return_statement => |statement| {
                if (statement.expression) |expression| try self.inferRequiredLiveInputsNode(function_id, expression, required);
                try self.inferRequiredLiveInputsRange(function_id, statement.cleanup, required);
            },
            .code_block => |child| try self.inferRequiredLiveInputsBlock(function_id, child, required),
            .type_initializer => |initializer| try self.inferRequiredLiveInputsNode(function_id, initializer.args, required),
            .auto_deinit_binding => |auto_id| try self.inferAutoDeinitRequiredLiveInputs(function_id, auto_id, required),
            else => {},
        }
    }

    fn inferRequiredLiveInputsRange(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        range: graph_mod.NodeRange,
        required: *std.array_list.Managed(facts.InputPath),
    ) anyerror!void {
        for (self.graph.node_refs.items[range.start..][0..range.len]) |node|
            try self.inferRequiredLiveInputsNode(function_id, node, required);
    }

    fn recordPointerUseRequirement(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        pointer: graph_mod.GlobalNodeId,
        required: *std.array_list.Managed(facts.InputPath),
    ) !void {
        const effect = try self.inferExpression(function_id, pointer);
        for (try self.symbolicSourcePaths(function_id, pointer, effect)) |path|
            try appendInputPath(required, path);
    }

    fn symbolicSourcePaths(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        effect: facts.ValueEffect,
    ) ![]const facts.InputPath {
        const direct = try self.inferInputPaths(function_id, node_id);
        if (direct.len != 0) return direct;
        return self.opaqueGenerationSourcePaths(effect);
    }

    fn substituteRequiredLiveInputs(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        callee_required: []const facts.InputPath,
        input: graph_mod.GlobalNodeId,
        required: *std.array_list.Managed(facts.InputPath),
    ) !void {
        try self.substituteRequiredLiveInputsWithOverride(function_id, callee_required, input, required, null);
    }

    fn substituteRequiredLiveInputsWithOverride(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        callee_required: []const facts.InputPath,
        input: graph_mod.GlobalNodeId,
        required: *std.array_list.Managed(facts.InputPath),
        override: ?SymbolicInputOverride,
    ) !void {
        const arguments = self.structArguments(input) orelse return;
        for (callee_required) |path| {
            if (path.input_index >= arguments.len) continue;
            const substituted = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (substituted) |candidate| try appendInputPath(required, candidate);
        }
    }

    fn substituteRequiredInputPath(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        path: facts.InputPath,
        arguments: []const graph_mod.ValueField,
        override: ?SymbolicInputOverride,
    ) ![]const facts.InputPath {
        if (path.input_index >= arguments.len) return &.{};
        if (override) |symbolic| if (symbolic.input_index == path.input_index) {
            if (path.projections.len == 0) return &.{};
            var effect = symbolic.effect;
            for (path.projections) |projection| effect = try self.projectValueEffect(effect, projection);
            return self.opaqueGenerationSourcePaths(effect);
        };

        const argument = arguments[path.input_index].value;
        var direct = try self.inferInputPaths(function_id, argument);
        if (direct.len != 0) {
            for (path.projections) |projection| direct = try self.projectInputPaths(direct, projection);
            return direct;
        }

        var effect = try self.inferExpression(function_id, argument);
        for (path.projections) |projection| effect = try self.projectValueEffect(effect, projection);
        return self.opaqueGenerationSourcePaths(effect);
    }

    fn inferAutoDeinitRequiredLiveInputs(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        auto_id: graph_mod.GlobalAutoDeinitId,
        required: *std.array_list.Managed(facts.InputPath),
    ) !void {
        const cleanup = self.graph.auto_deinits.items[@intFromEnum(auto_id)];
        const binding_effect = self.bindings.get(cleanup.binding);
        if (cleanup.input) |input| {
            try self.inferRequiredLiveInputsNode(function_id, input, required);
            if (cleanup.deinit_fn) |deinit_fn| {
                if (self.engine.summaryFor(deinit_fn)) |summary|
                    try self.substituteRequiredLiveInputsWithOverride(
                        function_id,
                        summary.required_live_inputs,
                        input,
                        required,
                        if (binding_effect) |effect| .{ .input_index = cleanup.self_field_index, .effect = effect } else null,
                    );
            }
        }
        if (binding_effect) |effect|
            try self.inferAutoDeinitFieldRequiredLiveInputs(function_id, cleanup.fields, effect, required);
    }

    fn inferAutoDeinitFieldRequiredLiveInputs(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        fields_range: primitives.Range(graph_mod.GlobalAutoDeinitFieldId),
        parent_effect: facts.ValueEffect,
        required: *std.array_list.Managed(facts.InputPath),
    ) !void {
        for (self.graph.auto_deinit_fields.items[fields_range.start..][0..fields_range.len]) |field| {
            const field_effect = try self.projectValueEffect(parent_effect, .{ .field = field.field_index });
            if (field.input) |input| {
                try self.inferRequiredLiveInputsNode(function_id, input, required);
                if (field.deinit_fn) |deinit_fn| {
                    if (self.engine.summaryFor(deinit_fn)) |summary|
                        try self.substituteRequiredLiveInputsWithOverride(
                            function_id,
                            summary.required_live_inputs,
                            input,
                            required,
                            .{ .input_index = field.self_field_index, .effect = field_effect },
                        );
                }
            }
            try self.inferAutoDeinitFieldRequiredLiveInputs(function_id, field.fields, field_effect, required);
        }
    }

    fn inferExpression(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
    ) anyerror!facts.ValueEffect {
        const node = self.graph.node(node_id);
        return switch (node.content) {
            .binding_use => |binding| if (self.inputIndex(function_id, binding)) |index|
                try self.inputValueEffect(index, &.{})
            else
                self.bindings.get(binding) orelse .{},
            .move_value => |value| try self.withOwnershipTransfer(try self.inferExpression(function_id, value)),
            .address_of => |value| .{ .input_places = try self.inferInputPaths(function_id, value) },
            .dereference => |value| try self.inferOpaqueRead(
                function_id,
                node_id,
                value.pointer,
                try self.inferExpression(function_id, value.pointer),
            ),
            .struct_value_literal => |literal| try self.inferAggregate(function_id, node_id, literal.fields),
            .list_literal => |literal| try self.inferElements(function_id, literal.elements),
            .array_literal => |literal| try self.inferElements(function_id, literal.elements),
            .choice_literal => |literal| try self.choiceValueEffect(
                self.variantIndex(literal.choice_type, literal.variant) orelse 0,
                if (literal.payload) |payload| try self.inferExpression(function_id, payload) else .{},
            ),
            .struct_field_access => |access| try self.inferOpaqueReadFromSyntax(
                function_id,
                node_id,
                try self.projectValueEffect(try self.inferExpression(function_id, access.value), .{ .field = access.field_index }),
            ),
            .choice_payload_access => |access| blk: {
                const choice = try self.inferExpression(function_id, access.value);
                const variant_index = self.variantIndex(self.graph.node(access.value).ty orelse break :blk .{}, access.variant) orelse break :blk .{};
                var payload: facts.ValueEffect = .{};
                for (choice.variants) |variant| if (variant.index == variant_index) {
                    payload = variant.value.*;
                    break;
                };
                break :blk try self.inferOpaqueReadFromSyntax(function_id, node_id, payload);
            },
            .array_index => |index| try self.inferOpaqueRead(
                function_id,
                node_id,
                index.array_ptr,
                try self.projectValueEffect(
                    try self.inferExpression(function_id, index.array_ptr),
                    if (self.staticIndex(index.index)) |value| .{ .static_index = value } else .dynamic_index,
                ),
            ),
            .explicit_cast => |cast| try self.inferExpression(function_id, cast.value),
            .function_call => |call| try self.inferCall(function_id, node_id, call.callee, call.input),
            .virtualize => |virtualize_id| try self.inferExpression(
                function_id,
                self.graph.virtualizes.items[@intFromEnum(virtualize_id)].value,
            ),
            .nullable_unwrap_or => |unwrap_id| blk: {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(unwrap_id)];
                break :blk try self.mergeValueEffects(
                    try self.inferExpression(function_id, unwrap.nullable_value),
                    try self.inferExpression(function_id, unwrap.fallback_value),
                );
            },
            else => .{},
        };
    }

    fn inferCall(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        call_node: graph_mod.GlobalNodeId,
        callee: graph_mod.GlobalFunctionId,
        input: graph_mod.GlobalNodeId,
    ) !facts.ValueEffect {
        const callee_function = self.graph.function(callee);
        const arguments = self.structArguments(input) orelse return .{};
        if (callee_function.safety_primitive != .none) {
            const effect = try self.primitiveValueEffect(callee_function.safety_primitive, self.freshSource(call_node, 0));
            return self.substituteOutput(function_id, effect, arguments);
        }
        const summary = self.engine.summaryFor(callee) orelse return .{};
        if (summary.outputs.len != 1) return .{};
        const substituted = try self.substituteOutput(function_id, summary.outputs[0], arguments);
        return self.rebaseFreshSources(substituted, call_node);
    }

    fn structArguments(self: *Infer, node_id: graph_mod.GlobalNodeId) ?[]const graph_mod.ValueField {
        const node = self.graph.node(node_id);
        const literal = switch (node.content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        return self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len];
    }

    fn inferAggregate(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        fields_range: primitives.Range(graph_mod.GlobalValueFieldId),
    ) !facts.ValueEffect {
        const node = self.graph.node(node_id);
        const ty = node.ty orelse return .{};
        const source_fields = self.graph.value_fields.items[fields_range.start..][0..fields_range.len];
        const output_fields = try self.allocator.alloc(facts.OutputFieldEffect, source_fields.len);
        var result: facts.ValueEffect = .{};
        for (source_fields, 0..) |field, position| {
            const hit = types.findField(self.graph, ty, self.graph.text(field.name)) orelse return error.InvalidType;
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.inferExpression(function_id, field.value);
            output_fields[position] = .{ .index = hit.index, .value = value };
            result = try self.mergeValueEffects(result, value.*);
            result.variants = &.{};
            result.known_choice_variant = null;
        }
        result.fields = output_fields;
        return result;
    }

    fn inferElements(self: *Infer, function_id: graph_mod.GlobalFunctionId, range: graph_mod.NodeRange) !facts.ValueEffect {
        var result: facts.ValueEffect = .{};
        const output_fields = try self.allocator.alloc(facts.OutputFieldEffect, range.len);
        for (self.graph.node_refs.items[range.start..][0..range.len], 0..) |element, index| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.inferExpression(function_id, element);
            output_fields[index] = .{ .index = @intCast(index), .value = value };
            result = try self.mergeValueEffects(result, value.*);
            result.variants = &.{};
            result.known_choice_variant = null;
        }
        result.fields = output_fields;
        return result;
    }

    fn inferOpaqueRead(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        pointer: graph_mod.GlobalNodeId,
        effect: facts.ValueEffect,
    ) !facts.ValueEffect {
        const ty = self.graph.node(node_id).ty orelse return .{};
        if (!self.typeContainsPointer(ty)) return .{};
        const input_paths = try self.inferInputPaths(function_id, pointer);
        var pointee = effect;
        if (input_paths.len != 0) {
            pointee.input_dependencies = &.{};
            pointee.input_places = &.{};
            pointee.input_place_values = input_paths;
        }
        const direct = try self.inferInputPaths(function_id, pointer);
        const sources = if (direct.len != 0) direct else try self.opaqueGenerationSourcePaths(pointee);
        return self.withOpaqueGenerationDependencies(sources, pointee);
    }

    fn inferOpaqueReadFromSyntax(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        effect: facts.ValueEffect,
    ) !facts.ValueEffect {
        const ty = self.graph.node(node_id).ty orelse return effect;
        if (!self.typeContainsPointer(ty)) return .{};
        return self.withOpaqueGenerationDependencies(try self.inferOpaqueReadInputPaths(function_id, node_id), effect);
    }

    fn inferOpaqueReadInputPaths(self: *Infer, function_id: graph_mod.GlobalFunctionId, node_id: graph_mod.GlobalNodeId) ![]const facts.InputPath {
        return switch (self.graph.node(node_id).content) {
            .move_value => |value| self.inferOpaqueReadInputPaths(function_id, value),
            .struct_field_access => |access| self.inferOpaqueReadInputPaths(function_id, access.value),
            .choice_payload_access => |access| self.inferOpaqueReadInputPaths(function_id, access.value),
            .dereference => |dereference| self.inferInputPaths(function_id, dereference.pointer),
            .array_index => |index| self.inferInputPaths(function_id, index.array_ptr),
            else => &.{},
        };
    }

    fn inferInputPaths(self: *Infer, function_id: graph_mod.GlobalFunctionId, node_id: graph_mod.GlobalNodeId) anyerror![]const facts.InputPath {
        return switch (self.graph.node(node_id).content) {
            .binding_use => |binding| if (self.inputIndex(function_id, binding)) |index|
                try self.oneInputPath(index, &.{})
            else
                self.place_bindings.get(binding) orelse &.{},
            .address_of => |value| self.inferInputPaths(function_id, value),
            .move_value => |value| self.inferInputPaths(function_id, value),
            .dereference => |value| self.inferInputPaths(function_id, value.pointer),
            .explicit_cast => |cast| self.inferInputPaths(function_id, cast.value),
            .struct_field_access => |access| self.projectInputPaths(
                try self.inferInputPaths(function_id, access.value),
                .{ .field = access.field_index },
            ),
            .choice_payload_access => |access| blk: {
                const ty = self.graph.node(access.value).ty orelse break :blk &.{};
                const index = self.variantIndex(ty, access.variant) orelse break :blk &.{};
                break :blk try self.projectInputPaths(try self.inferInputPaths(function_id, access.value), .{ .field = index });
            },
            .array_index => |index| self.projectInputPaths(
                try self.inferInputPaths(function_id, index.array_ptr),
                if (self.staticIndex(index.index)) |value| .{ .static_index = value } else .dynamic_index,
            ),
            else => &.{},
        };
    }

    fn substituteOutput(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        effect: facts.ValueEffect,
        arguments: []const graph_mod.ValueField,
    ) !facts.ValueEffect {
        return self.substituteOutputWithOverride(function_id, effect, arguments, null);
    }

    fn substituteOutputWithOverride(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        effect: facts.ValueEffect,
        arguments: []const graph_mod.ValueField,
        override: ?SymbolicInputOverride,
    ) !facts.ValueEffect {
        var result: facts.ValueEffect = .{
            .fresh_dependencies = effect.fresh_dependencies,
            .fresh_owned_roots = effect.fresh_owned_roots,
            .fresh_storage_capabilities = effect.fresh_storage_capabilities,
            .integer_address = effect.integer_address,
            .foreign_storage = effect.foreign_storage,
            .known_choice_variant = effect.known_choice_variant,
        };

        var input_places = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_places) |path| {
            const mapped = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (mapped) |candidate| try appendInputPath(&input_places, candidate);
        }
        result.input_places = try input_places.toOwnedSlice();

        var input_place_values = std.array_list.Managed(facts.InputPath).init(self.allocator);
        var input_place_value_overrides: facts.ValueEffect = .{};
        for (effect.input_place_values) |path| {
            if (path.input_index >= arguments.len) continue;
            if (override) |symbolic| if (symbolic.input_index == path.input_index) {
                var value = symbolic.effect;
                for (path.projections) |projection| value = try self.projectValueEffect(value, projection);
                input_place_value_overrides = try self.mergeValueEffects(input_place_value_overrides, value);
                continue;
            };
            const mapped = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (mapped) |candidate| try appendInputPath(&input_place_values, candidate);
        }
        result.input_place_values = try input_place_values.toOwnedSlice();
        result = try self.mergeValueEffects(result, input_place_value_overrides);

        var opaque_generations = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.opaque_generation_dependencies) |path| {
            const mapped = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (mapped) |candidate| try appendInputPath(&opaque_generations, candidate);
        }
        result.opaque_generation_dependencies = try opaque_generations.toOwnedSlice();

        var opaque_storages = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.opaque_storage_dependencies) |path| {
            const mapped = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (mapped) |candidate| try appendInputPath(&opaque_storages, candidate);
        }
        result.opaque_storage_dependencies = try opaque_storages.toOwnedSlice();

        for (effect.input_dependencies) |dependency| {
            if (dependency.path.input_index >= arguments.len) continue;
            if (override) |symbolic| {
                if (symbolic.input_index == dependency.path.input_index and dependency.path.projections.len == 0)
                    continue;
            }
            var argument = if (override) |symbolic|
                if (symbolic.input_index == dependency.path.input_index)
                    symbolic.effect
                else
                    try self.inferExpression(function_id, arguments[dependency.path.input_index].value)
            else
                try self.inferExpression(function_id, arguments[dependency.path.input_index].value);
            for (dependency.path.projections) |projection|
                argument = try self.projectValueEffect(argument, projection);
            argument = if (dependency.transfers_ownership)
                try self.withOwnershipTransfer(argument)
            else
                try self.withoutOwnershipTransfer(argument);
            result = try self.mergeValueEffects(result, argument);
        }

        if (effect.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
            for (effect.fields, 0..) |field, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.substituteOutputWithOverride(function_id, field.value.*, arguments, override);
                fields[index] = .{ .index = field.index, .value = value };
            }
            result.fields = fields;
        }
        if (effect.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
            for (effect.variants, 0..) |variant, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.substituteOutputWithOverride(function_id, variant.value.*, arguments, override);
                variants[index] = .{ .index = variant.index, .value = value };
            }
            result.variants = variants;
        }
        return result;
    }

    fn substitutePaths(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        paths: []const facts.InputPath,
        arguments: []const graph_mod.ValueField,
    ) ![]const facts.InputPath {
        var result = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (paths) |path| {
            if (path.input_index >= arguments.len) continue;
            var direct = try self.inferInputPaths(function_id, arguments[path.input_index].value);
            for (path.projections) |projection| direct = try self.projectInputPaths(direct, projection);
            for (direct) |candidate| try appendInputPath(&result, candidate);
        }
        return result.toOwnedSlice();
    }

    fn projectValueEffect(self: *Infer, effect: facts.ValueEffect, projection: facts.Projection) !facts.ValueEffect {
        switch (projection) {
            .field => |field_index| {
                for (effect.fields) |field| if (field.index == field_index) return field.value.*;
            },
            else => {},
        }
        var result = effect;
        const dependencies = try self.allocator.alloc(facts.InputDependency, effect.input_dependencies.len);
        for (effect.input_dependencies, 0..) |dependency, index| {
            dependencies[index] = dependency;
            dependencies[index].path.projections = try self.appendProjection(dependency.path.projections, projection);
        }
        result.input_dependencies = dependencies;
        result.input_places = try self.projectInputPaths(effect.input_places, projection);
        result.input_place_values = try self.projectInputPaths(effect.input_place_values, projection);
        result.fields = &.{};
        result.variants = &.{};
        result.known_choice_variant = null;
        return result;
    }

    fn projectInputPaths(self: *Infer, paths: []const facts.InputPath, projection: facts.Projection) ![]const facts.InputPath {
        const result = try self.allocator.alloc(facts.InputPath, paths.len);
        for (paths, 0..) |path, index| result[index] = .{
            .input_index = path.input_index,
            .projections = try self.appendProjection(path.projections, projection),
        };
        return result;
    }

    fn appendProjection(self: *Infer, projections: []const facts.Projection, projection: facts.Projection) ![]const facts.Projection {
        const result = try self.allocator.alloc(facts.Projection, projections.len + 1);
        @memcpy(result[0..projections.len], projections);
        result[projections.len] = projection;
        return result;
    }

    fn mergeValueEffects(self: *Infer, left: facts.ValueEffect, right: facts.ValueEffect) !facts.ValueEffect {
        var dependencies = std.array_list.Managed(facts.InputDependency).init(self.allocator);
        for (left.input_dependencies) |value| try appendInputDependency(&dependencies, value);
        for (right.input_dependencies) |value| try appendInputDependency(&dependencies, value);
        var input_places = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_places) |value| try appendInputPath(&input_places, value);
        for (right.input_places) |value| try appendInputPath(&input_places, value);
        var input_place_values = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_place_values) |value| try appendInputPath(&input_place_values, value);
        for (right.input_place_values) |value| try appendInputPath(&input_place_values, value);
        var opaque_generations = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.opaque_generation_dependencies) |value| try appendInputPath(&opaque_generations, value);
        for (right.opaque_generation_dependencies) |value| try appendInputPath(&opaque_generations, value);
        var opaque_storages = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.opaque_storage_dependencies) |value| try appendInputPath(&opaque_storages, value);
        for (right.opaque_storage_dependencies) |value| try appendInputPath(&opaque_storages, value);
        var fresh_dependencies = std.array_list.Managed(facts.FreshEffectSource).init(self.allocator);
        for (left.fresh_dependencies) |value| try appendFresh(&fresh_dependencies, value);
        for (right.fresh_dependencies) |value| try appendFresh(&fresh_dependencies, value);
        var fresh_owned = std.array_list.Managed(facts.FreshEffectSource).init(self.allocator);
        for (left.fresh_owned_roots) |value| try appendFresh(&fresh_owned, value);
        for (right.fresh_owned_roots) |value| try appendFresh(&fresh_owned, value);
        var fresh_capabilities = std.array_list.Managed(facts.FreshEffectSource).init(self.allocator);
        for (left.fresh_storage_capabilities) |value| try appendFresh(&fresh_capabilities, value);
        for (right.fresh_storage_capabilities) |value| try appendFresh(&fresh_capabilities, value);

        var fields = std.array_list.Managed(facts.OutputFieldEffect).init(self.allocator);
        for (left.fields) |left_field| {
            var merged = left_field.value.*;
            for (right.fields) |right_field| if (right_field.index == left_field.index) {
                merged = try self.mergeValueEffects(merged, right_field.value.*);
                break;
            };
            const stored = try self.allocator.create(facts.ValueEffect);
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

        var variants = std.array_list.Managed(facts.OutputVariantEffect).init(self.allocator);
        for (left.variants) |left_variant| {
            var merged = left_variant.value.*;
            for (right.variants) |right_variant| if (right_variant.index == left_variant.index) {
                merged = try self.mergeValueEffects(merged, right_variant.value.*);
                break;
            };
            const stored = try self.allocator.create(facts.ValueEffect);
            stored.* = merged;
            try variants.append(.{ .index = left_variant.index, .value = stored });
        }
        for (right.variants) |right_variant| {
            var found = false;
            for (left.variants) |left_variant| if (left_variant.index == right_variant.index) {
                found = true;
                break;
            };
            if (!found) try variants.append(right_variant);
        }

        return .{
            .input_dependencies = try dependencies.toOwnedSlice(),
            .input_places = try input_places.toOwnedSlice(),
            .input_place_values = try input_place_values.toOwnedSlice(),
            .opaque_generation_dependencies = try opaque_generations.toOwnedSlice(),
            .opaque_storage_dependencies = try opaque_storages.toOwnedSlice(),
            .fields = try fields.toOwnedSlice(),
            .variants = try variants.toOwnedSlice(),
            .known_choice_variant = if (left.variants.len == 0)
                right.known_choice_variant
            else if (right.variants.len == 0)
                left.known_choice_variant
            else if (left.known_choice_variant == right.known_choice_variant)
                left.known_choice_variant
            else
                null,
            .fresh_dependencies = try fresh_dependencies.toOwnedSlice(),
            .fresh_owned_roots = try fresh_owned.toOwnedSlice(),
            .integer_address = left.integer_address or right.integer_address,
            .foreign_storage = left.foreign_storage or right.foreign_storage,
            .fresh_storage_capabilities = try fresh_capabilities.toOwnedSlice(),
        };
    }

    fn withOwnershipTransfer(self: *Infer, effect: facts.ValueEffect) !facts.ValueEffect {
        var result = effect;
        const dependencies = try self.allocator.dupe(facts.InputDependency, effect.input_dependencies);
        for (dependencies) |*dependency| dependency.transfers_ownership = true;
        result.input_dependencies = dependencies;
        return result;
    }

    fn withoutOwnershipTransfer(self: *Infer, effect: facts.ValueEffect) !facts.ValueEffect {
        var result = effect;
        const dependencies = try self.allocator.dupe(facts.InputDependency, effect.input_dependencies);
        for (dependencies) |*dependency| dependency.transfers_ownership = false;
        result.input_dependencies = dependencies;
        return result;
    }

    fn choiceValueEffect(self: *Infer, variant_index: u32, payload: facts.ValueEffect) !facts.ValueEffect {
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, 1);
        const value = try self.allocator.create(facts.ValueEffect);
        value.* = payload;
        variants[0] = .{ .index = variant_index, .value = value };
        return .{ .variants = variants, .known_choice_variant = variant_index };
    }

    fn inputValueEffect(self: *Infer, input_index: u32, projections: []const facts.Projection) !facts.ValueEffect {
        const dependencies = try self.allocator.alloc(facts.InputDependency, 1);
        dependencies[0] = .{ .path = .{ .input_index = input_index, .projections = projections } };
        return .{ .input_dependencies = dependencies };
    }

    fn oneInputPath(self: *Infer, input_index: u32, projections: []const facts.Projection) ![]const facts.InputPath {
        const result = try self.allocator.alloc(facts.InputPath, 1);
        result[0] = .{ .input_index = input_index, .projections = projections };
        return result;
    }

    fn primitiveValueEffect(self: *Infer, primitive: primitives.SafetyPrimitive, source: facts.FreshEffectSource) !facts.ValueEffect {
        return switch (primitive) {
            .none, .relocate => .{},
            .establish_fresh_reference => .{ .fresh_dependencies = try self.oneFresh(source) },
            .establish_inherited_reference, .establish_inherited_storage => self.inputValueEffect(1, &.{}),
            .establish_allocation => self.ownedAllocationEffect(source),
            .raw_allocated_storage => .{ .foreign_storage = true, .fresh_storage_capabilities = try self.oneFresh(source) },
            .reference_offset,
            .mutable_reference_offset,
            .reinterpret_reference,
            .mutable_reinterpret_reference,
            .read_reference,
            => self.inputValueEffect(0, &.{}),
            .restrict_reference => blk: {
                var result = try self.mergeValueEffects(
                    try self.inputValueEffect(0, &.{}),
                    try self.inputValueEffect(1, &.{}),
                );
                result.input_places = try self.oneInputPath(0, &.{});
                break :blk result;
            },
            .trusted_opaque_move_out => .{
                .opaque_storage_dependencies = try self.oneInputPath(0, &.{}),
                .fresh_owned_roots = try self.oneFresh(source),
            },
            .trusted_opaque_move,
            .trusted_opaque_move_in,
            .trusted_opaque_relocate,
            .trusted_opaque_drop,
            .trusted_opaque_mark_empty,
            => .{},
        };
    }

    fn ownedAllocationEffect(self: *Infer, source: facts.FreshEffectSource) !facts.ValueEffect {
        const fields = try self.allocator.alloc(facts.OutputFieldEffect, 3);
        const data = try self.allocator.create(facts.ValueEffect);
        data.* = .{ .fresh_dependencies = try self.oneFresh(source) };
        const size = try self.allocator.create(facts.ValueEffect);
        size.* = .{};
        const allocator_effect = try self.allocator.create(facts.ValueEffect);
        allocator_effect.* = try self.inputValueEffect(2, &.{});
        fields[0] = .{ .index = 0, .value = data };
        fields[1] = .{ .index = 1, .value = size };
        fields[2] = .{ .index = 2, .value = allocator_effect };
        return .{ .fresh_owned_roots = try self.oneFresh(source), .fields = fields };
    }

    fn oneFresh(self: *Infer, source: facts.FreshEffectSource) ![]const facts.FreshEffectSource {
        const result = try self.allocator.alloc(facts.FreshEffectSource, 1);
        result[0] = source;
        return result;
    }

    fn rebaseFreshSources(self: *Infer, effect: facts.ValueEffect, call_node: graph_mod.GlobalNodeId) !facts.ValueEffect {
        var result = effect;
        result.fresh_dependencies = try self.rebaseFreshSlice(effect.fresh_dependencies, call_node);
        result.fresh_owned_roots = try self.rebaseFreshSlice(effect.fresh_owned_roots, call_node);
        result.fresh_storage_capabilities = try self.rebaseFreshSlice(effect.fresh_storage_capabilities, call_node);
        if (effect.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
            for (effect.fields, 0..) |field, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.rebaseFreshSources(field.value.*, call_node);
                fields[index] = .{ .index = field.index, .value = value };
            }
            result.fields = fields;
        }
        if (effect.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
            for (effect.variants, 0..) |variant, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.rebaseFreshSources(variant.value.*, call_node);
                variants[index] = .{ .index = variant.index, .value = value };
            }
            result.variants = variants;
        }
        return result;
    }

    fn rebaseFreshSlice(self: *Infer, sources: []const facts.FreshEffectSource, call_node: graph_mod.GlobalNodeId) ![]const facts.FreshEffectSource {
        const result = try self.allocator.alloc(facts.FreshEffectSource, sources.len);
        const call_raw: u32 = @intFromEnum(call_node);
        for (sources, 0..) |source, index| {
            var hash = std.hash.Wyhash.init(0);
            hash.update(std.mem.asBytes(&call_raw));
            hash.update(std.mem.asBytes(&source));
            result[index] = @intCast(hash.final());
        }
        return result;
    }

    fn withOpaqueGenerationDependencies(self: *Infer, paths: []const facts.InputPath, effect: facts.ValueEffect) !facts.ValueEffect {
        var result = effect;
        var dependencies = std.array_list.Managed(facts.InputPath).init(self.allocator);
        try dependencies.appendSlice(effect.opaque_generation_dependencies);
        for (paths) |path| try appendInputPath(&dependencies, path);
        result.opaque_generation_dependencies = try dependencies.toOwnedSlice();
        return result;
    }

    fn opaqueGenerationSourcePaths(self: *Infer, effect: facts.ValueEffect) ![]const facts.InputPath {
        if (effect.input_places.len != 0) return effect.input_places;
        var paths = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_dependencies) |dependency| try appendInputPath(&paths, dependency.path);
        return paths.toOwnedSlice();
    }

    fn inputIndex(self: *Infer, function_id: graph_mod.GlobalFunctionId, binding: graph_mod.GlobalBindingId) ?u32 {
        const function = self.graph.function(function_id);
        for (self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len], 0..) |candidate, index|
            if (candidate == binding) return @intCast(index);
        return null;
    }

    fn outputIndex(self: *Infer, function_id: graph_mod.GlobalFunctionId, binding: graph_mod.GlobalBindingId) ?usize {
        const function = self.graph.function(function_id);
        for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len], 0..) |candidate, index|
            if (candidate == binding) return index;
        return null;
    }

    fn variantIndex(self: *Infer, ty: graph_mod.GlobalTypeId, variant: graph_mod.GlobalVariantId) ?u32 {
        const range = types.variants(self.graph, ty) orelse return null;
        const raw = @intFromEnum(variant);
        if (raw < range.start or raw >= range.start + range.len) return null;
        return raw - range.start;
    }

    fn staticIndex(self: *Infer, node_id: graph_mod.GlobalNodeId) ?u32 {
        return switch (self.graph.node(node_id).content) {
            .int_literal => |value| if (value >= 0 and value <= std.math.maxInt(u32)) @intCast(value) else null,
            else => null,
        };
    }

    fn typeContainsPointer(self: *Infer, ty: graph_mod.GlobalTypeId) bool {
        return switch (self.graph.resolvedSemanticType(ty) orelse return false) {
            .pointer, .virtual => true,
            .array => |array| self.typeContainsPointer(array.element),
            .nullable => |child| self.typeContainsPointer(child),
            .inferred_errable => |child| self.typeContainsPointer(child),
            .structural, .declared, .generic => blk: {
                const range = types.fields(self.graph, ty) orelse break :blk false;
                for (self.graph.fields.items[range.start..][0..range.len]) |field|
                    if (self.typeContainsPointer(types.effectiveFieldType(field))) break :blk true;
                break :blk false;
            },
            .structural_choice, .inferred_choice => blk: {
                const range = types.variants(self.graph, ty) orelse break :blk false;
                for (self.graph.variants.items[range.start..][0..range.len]) |variant|
                    if (variant.payload_type) |payload| if (self.typeContainsPointer(payload)) break :blk true;
                break :blk false;
            },
            .builtin => false,
        };
    }

    fn freshSource(self: *Infer, node: graph_mod.GlobalNodeId, role: u32) facts.FreshEffectSource {
        _ = self;
        const node_raw: u32 = @intFromEnum(node);
        var hash = std.hash.Wyhash.init(0);
        hash.update(std.mem.asBytes(&node_raw));
        hash.update(std.mem.asBytes(&role));
        return @intCast(hash.final());
    }
};

fn pointerUseOperand(content: graph_mod.Node.Content) ?graph_mod.GlobalNodeId {
    return switch (content) {
        .dereference => |value| value.pointer,
        .array_index => |value| value.array_ptr,
        .array_store => |value| value.array_ptr,
        .struct_field_store => |value| value.struct_ptr,
        else => null,
    };
}

fn appendInputPath(list: *std.array_list.Managed(facts.InputPath), path: facts.InputPath) !void {
    for (list.items) |existing| {
        if (existing.input_index != path.input_index or existing.projections.len != path.projections.len) continue;
        var equal = true;
        for (existing.projections, path.projections) |left, right| if (!std.meta.eql(left, right)) {
            equal = false;
            break;
        };
        if (equal) return;
    }
    try list.append(path);
}

fn appendInputDependency(list: *std.array_list.Managed(facts.InputDependency), dependency: facts.InputDependency) !void {
    for (list.items) |existing| {
        if (existing.transfers_ownership != dependency.transfers_ownership) continue;
        var paths = std.array_list.Managed(facts.InputPath).init(list.allocator);
        defer paths.deinit();
        try paths.append(existing.path);
        const before = paths.items.len;
        try appendInputPath(&paths, dependency.path);
        if (paths.items.len == before) return;
    }
    try list.append(dependency);
}

fn appendFresh(list: *std.array_list.Managed(facts.FreshEffectSource), source: facts.FreshEffectSource) !void {
    for (list.items) |existing| if (existing == source) return;
    try list.append(source);
}

test "output summaries reach a fixed point through reverse call dependencies" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const int_ty: graph_mod.GlobalTypeId = @enumFromInt(0);
    const pointer_ty: graph_mod.GlobalTypeId = @enumFromInt(1);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.types.append(allocator, .{ .pointer = .{ .child = int_ty, .mutability = .read_only } });
    const empty_name = try graph.addString(allocator, "");
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };

    // wrapper(input0) -> output1 = identity(input0)
    // identity(input2) -> output3 = input2
    for (0..4) |_| try graph.bindings.append(allocator, .{
        .name = empty_name,
        .source = source,
        .ty = pointer_ty,
        .mutability = .variable,
    });
    try graph.binding_refs.appendSlice(allocator, &.{
        @as(graph_mod.GlobalBindingId, @enumFromInt(0)),
        @as(graph_mod.GlobalBindingId, @enumFromInt(1)),
        @as(graph_mod.GlobalBindingId, @enumFromInt(2)),
        @as(graph_mod.GlobalBindingId, @enumFromInt(3)),
    });

    const n0: graph_mod.GlobalNodeId = @enumFromInt(0);
    const n1: graph_mod.GlobalNodeId = @enumFromInt(1);
    const n2: graph_mod.GlobalNodeId = @enumFromInt(2);
    const n3: graph_mod.GlobalNodeId = @enumFromInt(3);
    const n4: graph_mod.GlobalNodeId = @enumFromInt(4);
    const n5: graph_mod.GlobalNodeId = @enumFromInt(5);
    try graph.nodes.append(allocator, .{ .source = source, .ty = pointer_ty, .content = .{ .binding_use = @enumFromInt(0) } });
    try graph.value_fields.append(allocator, .{ .name = empty_name, .value = n0 });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 1 } } } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = pointer_ty, .content = .{ .function_call = .{ .callee = @enumFromInt(1), .input = n1 } } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .assignment = .{ .binding = @enumFromInt(1), .value = n2 } } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = pointer_ty, .content = .{ .binding_use = @enumFromInt(2) } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .assignment = .{ .binding = @enumFromInt(3), .value = n4 } } });
    const n6: graph_mod.GlobalNodeId = @enumFromInt(6);
    try graph.nodes.append(allocator, .{ .source = source, .ty = int_ty, .content = .{ .dereference = .{ .pointer = n4, .ty = int_ty, .pointer_type = pointer_ty } } });
    try graph.node_refs.appendSlice(allocator, &.{ n3, n6, n5 });
    try graph.blocks.append(allocator, .{ .nodes = .{ .start = 0, .len = 1 } });
    try graph.blocks.append(allocator, .{ .nodes = .{ .start = 1, .len = 2 } });

    // Declaration identity is irrelevant to summary inference; valid slots keep
    // graph invariants intact for other consumers.
    for (0..2) |_| try graph.declarations.append(allocator, .{
        .kind = .function,
        .name = empty_name,
        .source = source,
    });
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
        .body = @enumFromInt(0),
        .input_bindings = .{ .start = 0, .len = 1 },
        .output_bindings = .{ .start = 1, .len = 1 },
    });
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(1),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
        .body = @enumFromInt(1),
        .input_bindings = .{ .start = 2, .len = 1 },
        .output_bindings = .{ .start = 3, .len = 1 },
    });
    try graph.function_operators.appendSlice(allocator, &.{ null, null });

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const summary_allocator = arena.allocator();
    var engine = summaries.Engine.init(summary_allocator);
    defer engine.deinit();
    var infer = Infer.init(summary_allocator, &graph, &engine);
    defer infer.deinit();
    try infer.inferOutputFixedPoint();

    const wrapper = engine.summaries.get(@enumFromInt(0)).?;
    const identity = engine.summaries.get(@enumFromInt(1)).?;
    try std.testing.expectEqual(@as(usize, 1), identity.outputs.len);
    try std.testing.expectEqual(@as(usize, 1), identity.outputs[0].input_dependencies.len);
    try std.testing.expectEqual(@as(u32, 0), identity.outputs[0].input_dependencies[0].path.input_index);
    try std.testing.expectEqual(@as(usize, 1), wrapper.outputs[0].input_dependencies.len);
    try std.testing.expectEqual(@as(u32, 0), wrapper.outputs[0].input_dependencies[0].path.input_index);

    try std.testing.expectEqual(@as(usize, 1), identity.required_live_inputs.len);
    try std.testing.expectEqual(@as(u32, 0), identity.required_live_inputs[0].input_index);
    try std.testing.expectEqual(@as(usize, 1), wrapper.required_live_inputs.len);
    try std.testing.expectEqual(@as(u32, 0), wrapper.required_live_inputs[0].input_index);
}

test "input post-state joins retain caller-visible transitions" {
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(std.testing.allocator);
    var engine = summaries.Engine.init(std.testing.allocator);
    defer engine.deinit();
    var inference = Infer.init(std.testing.allocator, &graph, &engine);
    defer inference.deinit();

    var states = std.array_list.Managed(facts.PlacePostState).init(std.testing.allocator);
    defer states.deinit();
    const target = facts.InputPath{ .input_index = 0 };

    try inference.recordInputPostState(&states, &.{target}, .initialized, .{}, false, false, false, false);
    try std.testing.expectEqual(@as(usize, 1), states.items.len);
    try std.testing.expectEqual(value_state.Initializedness.initialized, states.items[0].initializedness);
    try std.testing.expect(!states.items[0].refreshes_storage_generation);

    try inference.recordInputPostState(&states, &.{target}, .deinitialized, .{}, true, false, false, false);
    try inference.recordInputPostState(&states, &.{target}, .initialized, .{}, false, false, false, false);
    try std.testing.expect(states.items[0].refreshes_storage_generation);

    var changed = std.array_list.Managed(facts.PlacePostState).init(std.testing.allocator);
    defer changed.deinit();
    try changed.append(.{ .target = target, .initializedness = .moved });
    var unchanged = std.array_list.Managed(facts.PlacePostState).init(std.testing.allocator);
    defer unchanged.deinit();
    var joined = std.array_list.Managed(facts.PlacePostState).init(std.testing.allocator);
    defer joined.deinit();
    try inference.joinInputPostStates(&joined, &changed, &unchanged);
    try std.testing.expectEqual(value_state.Initializedness.maybe_initialized, joined.items[0].initializedness);
}

test "opaque ownership post-state joins preserve storage correlation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var engine = summaries.Engine.init(allocator);
    defer engine.deinit();
    var inference = Infer.init(allocator, &graph, &engine);
    defer inference.deinit();

    const target = facts.InputPath{ .input_index = 0 };
    const storage = facts.InputPath{ .input_index = 1 };
    const other_storage = facts.InputPath{ .input_index = 2 };
    var opaque_branch = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer opaque_branch.deinit();
    try inference.recordOpaqueOwnershipConsumption(&opaque_branch, &.{target}, .definite, storage);
    var plain = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer plain.deinit();
    var conditional = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer conditional.deinit();
    try inference.joinInputPostStates(&conditional, &opaque_branch, &plain);
    try std.testing.expectEqual(facts.OpaqueOwnershipConsumption.conditional, conditional.items[0].opaque_ownership);
    try std.testing.expect(inference.optionalInputPathEqual(storage, conditional.items[0].opaque_storage));

    var other = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer other.deinit();
    try inference.recordOpaqueOwnershipConsumption(&other, &.{target}, .definite, other_storage);
    var ambiguous = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer ambiguous.deinit();
    try inference.joinInputPostStates(&ambiguous, &opaque_branch, &other);
    try std.testing.expectEqual(facts.OpaqueOwnershipConsumption.ambiguous, ambiguous.items[0].opaque_ownership);
    try std.testing.expect(ambiguous.items[0].opaque_storage == null);
}

fn joinInitializedness(left: value_state.Initializedness, right: value_state.Initializedness) value_state.Initializedness {
    if (left == right) return left;
    return .maybe_initialized;
}
