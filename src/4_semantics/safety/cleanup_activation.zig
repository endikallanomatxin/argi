const std = @import("std");
const graph_mod = @import("../global/graph.zig");
const types = @import("../global/types.zig");
const facts = @import("facts.zig");
const primitives = @import("../primitives/schema.zig");

/// Cleanup summaries describe destructors that can actually run. Runtime drop
/// flags suppress moved values and inactive payloads; this symbolic traversal
/// preserves those same conditions before collecting any destructor effects.
/// The result unions possible cleanup across exits, without caller snapshots.
pub const Activation = struct {
    roots: std.AutoHashMap(graph_mod.GlobalAutoDeinitId, void),
    fields: std.AutoHashMap(graph_mod.GlobalAutoDeinitFieldId, void),
    stable_initializers: std.AutoHashMap(graph_mod.GlobalBindingId, graph_mod.GlobalNodeId),
    unstable_bindings: std.AutoHashMap(graph_mod.GlobalBindingId, void),
    incomplete_outputs: std.AutoHashMap(graph_mod.GlobalBindingId, void),
    output_bindings: []const graph_mod.GlobalBindingId,
    assignment_counts: []usize,
    loop_assigned: []bool,

    pub fn canForward(self: *const Activation, binding: graph_mod.GlobalBindingId) bool {
        if (self.incomplete_outputs.contains(binding)) return false;
        for (self.output_bindings, 0..) |output, index| if (output == binding)
            return self.assignment_counts[index] == 1 and !self.loop_assigned[index];
        return false;
    }

    pub fn stableInitializer(self: *const Activation, binding: graph_mod.GlobalBindingId) ?graph_mod.GlobalNodeId {
        if (self.unstable_bindings.contains(binding)) return null;
        return self.stable_initializers.get(binding);
    }

    pub fn deinit(self: *Activation) void {
        self.stable_initializers.deinit();
        self.unstable_bindings.deinit();
        self.incomplete_outputs.deinit();
        self.roots.allocator.free(self.assignment_counts);
        self.roots.allocator.free(self.loop_assigned);
        self.roots.deinit();
        self.fields.deinit();
    }
};

const Flow = struct {
    disabled: std.array_list.Managed(facts.Place),
    assigned_outputs: std.array_list.Managed(graph_mod.GlobalBindingId),
    reachable: bool = true,

    fn init(allocator: std.mem.Allocator) Flow {
        return .{ .disabled = .init(allocator), .assigned_outputs = .init(allocator) };
    }
    fn deinit(self: *Flow) void {
        self.disabled.deinit();
        self.assigned_outputs.deinit();
    }
    fn clone(self: *const Flow, allocator: std.mem.Allocator) !Flow {
        var result = Flow.init(allocator);
        try result.disabled.appendSlice(self.disabled.items);
        try result.assigned_outputs.appendSlice(self.assigned_outputs.items);
        result.reachable = self.reachable;
        return result;
    }
    fn skips(self: *const Flow, place: facts.Place) bool {
        for (self.disabled.items) |disabled| if (disabled.isPrefixOf(place)) return true;
        return false;
    }
    fn disable(self: *Flow, place: facts.Place) !void {
        if (!self.skips(place)) try self.disabled.append(place);
    }
    fn initialize(self: *Flow, place: facts.Place) void {
        var index: usize = 0;
        while (index < self.disabled.items.len) {
            const disabled = self.disabled.items[index];
            if (place.isPrefixOf(disabled) or disabled.isPrefixOf(place)) {
                // A write through a previously moved aggregate conservatively
                // enables its cleanup again. Initializedness remains checked
                // by the ordinary checker rather than inferred from this mask.
                _ = self.disabled.swapRemove(index);
            } else index += 1;
        }
    }
    fn join(self: *Flow, other: *const Flow, allocator: std.mem.Allocator) !void {
        if (!other.reachable) return;
        if (!self.reachable) {
            self.disabled.clearRetainingCapacity();
            try self.disabled.appendSlice(other.disabled.items);
            self.assigned_outputs.clearRetainingCapacity();
            try self.assigned_outputs.appendSlice(other.assigned_outputs.items);
            self.reachable = true;
            return;
        }
        var common = Flow.init(allocator);
        defer common.deinit();
        for (self.assigned_outputs.items) |binding| if (std.mem.indexOfScalar(graph_mod.GlobalBindingId, other.assigned_outputs.items, binding) != null) try common.assigned_outputs.append(binding);
        for (self.disabled.items) |left| for (other.disabled.items) |right| {
            if (left.isPrefixOf(right)) try common.disable(right) else if (right.isPrefixOf(left)) try common.disable(left);
        };
        self.disabled.clearRetainingCapacity();
        try self.disabled.appendSlice(common.disabled.items);
        self.assigned_outputs.clearRetainingCapacity();
        try self.assigned_outputs.appendSlice(common.assigned_outputs.items);
    }
};

pub fn collect(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, function_id: graph_mod.GlobalFunctionId) !Activation {
    const function = graph.function(function_id);
    const counts = try allocator.alloc(usize, function.output_bindings.len);
    @memset(counts, 0);
    const loop_assigned = allocator.alloc(bool, function.output_bindings.len) catch |err| {
        allocator.free(counts);
        return err;
    };
    @memset(loop_assigned, false);
    var scanner = Scanner{
        .allocator = allocator,
        .graph = graph,
        .assignment_nodes = .init(allocator),
        .activation = .{
            .stable_initializers = .init(allocator),
            .unstable_bindings = .init(allocator),
            .incomplete_outputs = .init(allocator),
            .roots = .init(allocator),
            .fields = .init(allocator),
            .output_bindings = graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len],
            .assignment_counts = counts,
            .loop_assigned = loop_assigned,
        },
    };
    errdefer scanner.activation.deinit();
    defer scanner.assignment_nodes.deinit();
    var flow = Flow.init(allocator);
    defer flow.deinit();
    if (graph.function(function_id).body) |body| try scanner.block(body, &flow);
    if (flow.reachable) try scanner.recordOutputExit(&flow);
    return scanner.activation;
}

const Scanner = struct {
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,
    activation: Activation,
    in_loop: bool = false,
    assignment_nodes: std.AutoHashMap(graph_mod.GlobalNodeId, void),

    fn recordOutputExit(self: *Scanner, flow: *const Flow) !void {
        for (self.activation.output_bindings) |binding| {
            if (std.mem.indexOfScalar(graph_mod.GlobalBindingId, flow.assigned_outputs.items, binding) == null)
                try self.activation.incomplete_outputs.put(binding, {});
        }
    }

    fn recordAssignment(self: *Scanner, id: graph_mod.GlobalNodeId, binding: graph_mod.GlobalBindingId) !void {
        const seen = try self.assignment_nodes.getOrPut(id);
        for (self.activation.output_bindings, 0..) |output, index| if (output == binding) {
            if (!seen.found_existing) self.activation.assignment_counts[index] += 1;
            self.activation.loop_assigned[index] = self.activation.loop_assigned[index] or self.in_loop;
        };
    }

    fn project(self: *Scanner, place: facts.Place, projection: facts.Projection) !facts.Place {
        const path = try self.allocator.alloc(facts.Projection, place.projections.len + 1);
        @memcpy(path[0..place.projections.len], place.projections);
        path[place.projections.len] = projection;
        return .{ .root = place.root, .projections = path };
    }

    fn resolvePlace(self: *Scanner, node_id: graph_mod.GlobalNodeId) anyerror!?facts.Place {
        return switch (self.graph.node(node_id).content) {
            .binding_use => |binding| .{ .root = binding },
            .address_of, .move_value, .denied_implicit_copy => |child| try self.resolvePlace(child),
            .dereference => |deref| try self.resolvePlace(deref.pointer),
            .struct_field_access => |access| if (try self.resolvePlace(access.value)) |parent| try self.project(parent, .{ .field = access.field_index }) else null,
            .choice_payload_access => |access| blk: {
                const parent = try self.resolvePlace(access.value) orelse break :blk null;
                const ty = self.graph.node(access.value).ty orelse break :blk null;
                const range = types.variants(self.graph, ty) orelse break :blk null;
                break :blk try self.project(parent, .{ .variant = @intFromEnum(access.variant) - range.start });
            },
            else => null,
        };
    }

    fn refine(self: *Scanner, flow: *Flow, target: facts.Place, ty: graph_mod.GlobalTypeId, variant: graph_mod.GlobalVariantId, active: bool) !void {
        const variants = types.variants(self.graph, ty) orelse return;
        const selected = @intFromEnum(variant) - variants.start;
        for (0..variants.len) |index| {
            if ((index == selected) == active) continue;
            try flow.disable(try self.project(target, .{ .variant = @intCast(index) }));
        }
    }

    fn initialize(self: *Scanner, flow: *Flow, target: facts.Place, value: graph_mod.GlobalNodeId) anyerror!void {
        flow.initialize(target);
        switch (self.graph.node(value).content) {
            .choice_literal => |literal| {
                try self.refine(flow, target, literal.choice_type, literal.variant, true);
                if (literal.payload) |payload| {
                    const variants = types.variants(self.graph, literal.choice_type) orelse return;
                    try self.initialize(flow, try self.project(target, .{ .variant = @intFromEnum(literal.variant) - variants.start }), payload);
                }
            },
            .struct_value_literal => |literal| for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |field, index| {
                try self.initialize(flow, try self.project(target, .{ .field = @intCast(index) }), field.value);
            },
            else => {},
        }
    }

    fn cleanupFields(self: *Scanner, range: primitives.Range(graph_mod.GlobalAutoDeinitFieldId), parent: facts.Place, flow: *const Flow) anyerror!void {
        for (self.graph.auto_deinit_fields.items[range.start..][0..range.len], 0..) |field, index| {
            const target = try self.project(parent, if (field.is_variant) .{ .variant = field.field_index } else .{ .field = field.field_index });
            if (flow.skips(target)) continue;
            try self.activation.fields.put(@enumFromInt(range.start + @as(u32, @intCast(index))), {});
            try self.cleanupFields(field.fields, target, flow);
        }
    }

    fn block(self: *Scanner, id: graph_mod.GlobalBlockId, flow: *Flow) anyerror!void {
        const value = self.graph.blocks.items[@intFromEnum(id)];
        try self.visitRange(value.nodes, flow);
        if (flow.reachable) if (value.ret_val) |result| try self.node(result, flow);
    }

    fn visitRange(self: *Scanner, nodes: primitives.Range(graph_mod.GlobalNodeId), flow: *Flow) anyerror!void {
        for (self.graph.node_refs.items[nodes.start..][0..nodes.len]) |id| {
            if (!flow.reachable) break;
            try self.node(id, flow);
        }
    }

    fn conditional(self: *Scanner, id: graph_mod.GlobalNodeId, flow: *Flow) anyerror!void {
        var branch = try flow.clone(self.allocator);
        defer branch.deinit();
        try self.node(id, &branch);
        try flow.join(&branch, self.allocator);
    }

    fn node(self: *Scanner, id: graph_mod.GlobalNodeId, flow: *Flow) anyerror!void {
        switch (self.graph.node(id).content) {
            .code_block, .value_sequence => |child| try self.block(child, flow),
            .binding_declaration => |binding| {
                const record = self.graph.binding(binding);
                if (self.in_loop or record.deferred_initialization) {
                    try self.activation.unstable_bindings.put(binding, {});
                } else if (record.initialization) |initialization| try self.activation.stable_initializers.put(binding, initialization);
                const target = facts.Place{ .root = binding };
                if (!record.deferred_initialization and record.initialization != null) {
                    try self.node(record.initialization.?, flow);
                    try self.initialize(flow, target, record.initialization.?);
                } else try flow.disable(target);
            },
            .assignment => |assignment| {
                try self.recordAssignment(id, assignment.binding);
                try self.activation.unstable_bindings.put(assignment.binding, {});
                try self.node(assignment.value, flow);
                try self.initialize(flow, .{ .root = assignment.binding }, assignment.value);
                if (std.mem.indexOfScalar(graph_mod.GlobalBindingId, self.activation.output_bindings, assignment.binding) != null and
                    std.mem.indexOfScalar(graph_mod.GlobalBindingId, flow.assigned_outputs.items, assignment.binding) == null)
                    try flow.assigned_outputs.append(assignment.binding);
            },
            .move_value => |value| {
                try self.node(value, flow);
                if (try self.resolvePlace(value)) |target| try flow.disable(target);
            },
            .address_of => |value| {
                if (try self.resolvePlace(value)) |target| try self.activation.unstable_bindings.put(target.root, {});
                try self.node(value, flow);
            },
            .denied_implicit_copy => |value| try self.node(value, flow),
            .dereference => |value| try self.node(value.pointer, flow),
            .struct_field_access => |access| try self.node(access.value, flow),
            .choice_payload_access => |access| try self.node(access.value, flow),
            .struct_value_literal => |literal| for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| try self.node(field.value, flow),
            .choice_literal => |literal| if (literal.payload) |payload| try self.node(payload, flow),
            .list_literal => |literal| try self.visitRange(literal.elements, flow),
            .array_literal => |literal| try self.visitRange(literal.elements, flow),
            .if_statement => |statement| {
                try self.node(statement.condition, flow);
                var left = try flow.clone(self.allocator);
                defer left.deinit();
                var right = try flow.clone(self.allocator);
                defer right.deinit();
                if (statement.choice_test) |choice_test| if (try self.resolvePlace(choice_test.choice_value)) |target| {
                    const ty = self.graph.node(choice_test.choice_value).ty.?;
                    try self.refine(&left, target, ty, choice_test.variant, choice_test.then_has_variant);
                    try self.refine(&right, target, ty, choice_test.variant, !choice_test.then_has_variant);
                };
                try self.block(statement.then_block, &left);
                if (statement.else_block) |child| try self.block(child, &right);
                try left.join(&right, self.allocator);
                flow.disabled.clearRetainingCapacity();
                try flow.disabled.appendSlice(left.disabled.items);
                flow.assigned_outputs.clearRetainingCapacity();
                try flow.assigned_outputs.appendSlice(left.assigned_outputs.items);
                flow.reachable = left.reachable;
            },
            .switch_statement => |switch_id| {
                const statement = self.graph.switches.items[@intFromEnum(switch_id)];
                try self.node(statement.expression, flow);
                var joined = Flow.init(self.allocator);
                joined.reachable = false;
                defer joined.deinit();
                for (self.graph.switch_cases.items[statement.cases.start..][0..statement.cases.len]) |case| {
                    var branch = try flow.clone(self.allocator);
                    defer branch.deinit();
                    if (try self.resolvePlace(statement.expression)) |target| {
                        try self.refine(&branch, target, self.graph.node(statement.expression).ty.?, case.variant, true);
                        if (case.payload_binding != null and case.payload_mode == .move) try branch.disable(target);
                    }
                    if (case.payload_binding) |binding| branch.initialize(.{ .root = binding });
                    try self.block(case.body, &branch);
                    try joined.join(&branch, self.allocator);
                }
                if (statement.default_block) |child| {
                    var branch = try flow.clone(self.allocator);
                    defer branch.deinit();
                    try self.block(child, &branch);
                    try joined.join(&branch, self.allocator);
                } else if (!statement.exhaustive) try joined.join(flow, self.allocator);
                flow.disabled.clearRetainingCapacity();
                try flow.disabled.appendSlice(joined.disabled.items);
                flow.assigned_outputs.clearRetainingCapacity();
                try flow.assigned_outputs.appendSlice(joined.assigned_outputs.items);
                flow.reachable = joined.reachable;
            },
            .while_statement => |statement| {
                const previous_loop = self.in_loop;
                self.in_loop = true;
                defer self.in_loop = previous_loop;
                try self.node(statement.condition, flow);
                var body = try flow.clone(self.allocator);
                defer body.deinit();
                try self.block(statement.body, &body);
                // Forget moves across loop iterations. This retains may-cleanup
                // rather than proving a destructor absent from a single visit.
                flow.disabled.clearRetainingCapacity();
            },
            .for_statement => |statement| {
                const previous_loop = self.in_loop;
                self.in_loop = true;
                defer self.in_loop = previous_loop;
                if (statement.init) |initialization| try self.node(initialization, flow);
                try self.node(statement.condition, flow);
                var body = try flow.clone(self.allocator);
                defer body.deinit();
                try self.block(statement.body, &body);
                if (body.reachable) if (statement.increment) |increment| try self.node(increment, &body);
                flow.disabled.clearRetainingCapacity();
            },
            .return_statement => |statement| {
                if (statement.expression) |value| try self.node(value, flow);
                try self.visitRange(statement.cleanup, flow);
                try self.recordOutputExit(flow);
                flow.reachable = false;
            },
            .break_statement, .continue_statement => flow.reachable = false,
            .auto_deinit_binding => |auto_id| {
                const cleanup = self.graph.auto_deinits.items[@intFromEnum(auto_id)];
                const target = facts.Place{ .root = cleanup.binding };
                if (!flow.skips(target)) {
                    try self.activation.roots.put(auto_id, {});
                    try self.cleanupFields(cleanup.fields, target, flow);
                }
                try flow.disable(target);
            },
            .function_call => |call| {
                if (call.callee_value) |value| try self.node(value, flow);
                try self.node(call.input, flow);
                if (call.consumes_auto_deinit) |value| if (try self.resolvePlace(value)) |target| try flow.disable(target);
                if (call.initializes_auto_deinit) |value| if (try self.resolvePlace(value)) |target| flow.initialize(target);
            },
            .virtual_call => |call_id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(call_id)];
                try self.node(call.handle, flow);
                try self.node(call.input, flow);
            },
            .virtualize => |value| try self.node(self.graph.virtualizes.items[@intFromEnum(value)].value, flow),
            .binary_operation => |value| {
                try self.node(value.left, flow);
                try self.node(value.right, flow);
            },
            .comparison => |value| {
                try self.node(value.left, flow);
                try self.node(value.right, flow);
            },
            .logical_operation => |value| {
                try self.node(value.left, flow);
                try self.conditional(value.right, flow);
            },
            .struct_field_store => |value| {
                try self.node(value.struct_ptr, flow);
                try self.node(value.value, flow);
                if (try self.resolvePlace(value.struct_ptr)) |parent| try self.initialize(flow, try self.project(parent, .{ .field = value.field_index }), value.value);
            },
            .array_index => |value| {
                try self.node(value.array_ptr, flow);
                try self.node(value.index, flow);
            },
            .array_store => |value| {
                try self.node(value.array_ptr, flow);
                try self.node(value.index, flow);
                try self.node(value.value, flow);
            },
            .pointer_assignment => |value| {
                try self.node(value.pointer, flow);
                try self.node(value.value, flow);
                // An unresolved indirect write may reinitialize an owner whose
                // address escaped. Forget skip proofs rather than guess aliases.
                flow.disabled.clearRetainingCapacity();
            },
            .explicit_cast => |value| try self.node(value.value, flow),
            .nullable_unwrap_or => |value| {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(value)];
                try self.node(unwrap.nullable_value, flow);
                try self.conditional(unwrap.fallback_value, flow);
            },
            .error_propagation => |value| {
                const propagation = self.graph.error_propagations.items[@intFromEnum(value)];
                try self.node(propagation.errable_value, flow);
                var failed = try flow.clone(self.allocator);
                defer failed.deinit();
                try self.visitRange(propagation.cleanup_nodes, &failed);
                try self.recordOutputExit(&failed);
            },
            .error_context => |value| {
                const context = self.graph.error_contexts.items[@intFromEnum(value)];
                try self.node(context.errable_value, flow);
                try self.node(context.context, flow);
                var failed = try flow.clone(self.allocator);
                defer failed.deinit();
                try self.visitRange(context.cleanup_nodes, &failed);
                try self.recordOutputExit(&failed);
            },
            .testing_expect_error => |value| {
                const expect = self.graph.testing_expect_errors.items[@intFromEnum(value)];
                try self.node(expect.expected_reason, flow);
                try self.node(expect.actual_result, flow);
                if (expect.test_fail_input) |input| try self.conditional(input, flow);
            },
            else => {},
        }
    }
};
