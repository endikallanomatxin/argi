const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const resolution = @import("resolution.zig");
const core_mod = @import("core.zig");
const global_types = @import("types.zig");
const primitives = @import("../primitives/schema.zig");

pub const Stats = struct {
    propagations: u32 = 0,
    contexts: u32 = 0,
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    stats: Stats = .{},

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        _ = module_index;
        _ = module;
        return switch (operation) {
            .resolve_error_propagation => |value| resolution.Result.fromBool(try self.resolve(o, value)),
            else => .not_applicable,
        };
    }

    fn resolve(self: *Resolver, o: globalizer.Offsets, value: anytype) !bool {
        const errable = globalizer.globalNode(o, value.errable_value);
        const errable_ty = self.graph.nodes.items[@intFromEnum(errable)].ty orelse return false;
        const ok = global_types.findVariant(self.graph, errable_ty, "ok") orelse return false;
        const err = global_types.findVariant(self.graph, errable_ty, "error") orelse return false;
        const ok_payload = ok.variant.payload_type orelse try self.builtin(.Void);
        const error_payload = err.variant.payload_type orelse try self.builtin(.Void);
        const result_ty = unwrapSingleField(self.graph, ok_payload) orelse ok_payload;

        const target = globalizer.globalNode(o, value.node);
        const propagated_ty = self.enclosingErrableType(target) orelse errable_ty;
        const propagated_error = global_types.findVariant(self.graph, propagated_ty, "error") orelse err;
        const propagated_error_payload = propagated_error.variant.payload_type orelse error_payload;
        if (!self.errorPayloadCanPropagate(error_payload, propagated_error_payload))
            return error.IncompatibleErrorPayload;
        const source = self.graph.nodes.items[@intFromEnum(errable)].source;
        const empty = try self.graph.addString(self.allocator, "");
        const cleanup: primitives.Range(global_sg.GlobalNodeId) = .{ .start = @intCast(self.graph.node_refs.items.len), .len = 0 };

        if (value.context) |local_context| {
            const context = globalizer.globalNode(o, local_context);
            const id: global_sg.GlobalErrorContextId = @enumFromInt(@as(u32, @intCast(self.graph.error_contexts.items.len)));
            try self.graph.error_contexts.append(self.allocator, .{
                .errable_value = errable,
                .context = context,
                .cleanup_nodes = cleanup,
                .ok_variant = ok.id,
                .ok_value_field_index = singleFieldIndex(self.graph, ok_payload),
                .error_variant = err.id,
                .propagated_errable_type = propagated_ty,
                .propagated_error_variant = propagated_error.id,
                .ok_payload_type = ok_payload,
                .error_payload_type = error_payload,
                .propagated_error_payload_type = propagated_error_payload,
                .diagnostic_line = 0,
                .diagnostic_column = 0,
                .diagnostic_source_line = empty,
            });
            self.graph.nodes.items[@intFromEnum(target)] = .{
                .source = source,
                .ty = result_ty,
                .content = .{ .error_context = id },
            };
            self.stats.contexts += 1;
        } else {
            const id: global_sg.GlobalErrorPropagationId = @enumFromInt(@as(u32, @intCast(self.graph.error_propagations.items.len)));
            try self.graph.error_propagations.append(self.allocator, .{
                .errable_value = errable,
                .cleanup_nodes = cleanup,
                .ok_variant = ok.id,
                .ok_value_field_index = singleFieldIndex(self.graph, ok_payload),
                .error_variant = err.id,
                .propagated_errable_type = propagated_ty,
                .propagated_error_variant = propagated_error.id,
                .ok_payload_type = ok_payload,
                .error_payload_type = error_payload,
                .propagated_error_payload_type = propagated_error_payload,
                .diagnostic_line = 0,
                .diagnostic_column = 0,
                .diagnostic_source_line = empty,
            });
            self.graph.nodes.items[@intFromEnum(target)] = .{
                .source = source,
                .ty = result_ty,
                .content = .{ .error_propagation = id },
            };
            self.stats.propagations += 1;
        }
        return true;
    }

    fn enclosingErrableType(self: *Resolver, target: global_sg.GlobalNodeId) ?global_sg.GlobalTypeId {
        for (self.graph.functions.items) |function| {
            const body = function.body orelse continue;
            if (!self.blockContains(body, target)) continue;
            if (function.output.len == 0) return null;
            if (function.output.len == 1) {
                const ty = self.graph.fields.items[function.output.start].ty;
                if (global_types.findVariant(self.graph, ty, "error") != null) return ty;
            }
            return null;
        }
        return null;
    }

    fn errorPayloadCanPropagate(self: *const Resolver, source: global_sg.GlobalTypeId, target: global_sg.GlobalTypeId) bool {
        if (global_types.equal(self.graph, source, target)) return true;
        const source_reason = global_types.findField(self.graph, source, "reason") orelse return false;
        const target_reason = global_types.findField(self.graph, target, "reason") orelse return false;
        const source_trace = global_types.findField(self.graph, source, "trace") orelse return false;
        const target_trace = global_types.findField(self.graph, target, "trace") orelse return false;
        if (!global_types.equal(self.graph, source_trace.field.ty, target_trace.field.ty)) return false;
        const source_variants = global_types.variants(self.graph, source_reason.field.ty) orelse return false;
        if (self.graph.resolvedSemanticType(target_reason.field.ty)) |ty| switch (ty) {
            .inferred_choice => |choice| if (choice.kind == .reasons) return true,
            else => {},
        };
        for (self.graph.variants.items[source_variants.start..][0..source_variants.len]) |variant| {
            const matching = global_types.findVariant(self.graph, target_reason.field.ty, self.graph.text(variant.name)) orelse return false;
            if (variant.payload_type) |payload| {
                const target_payload = matching.variant.payload_type orelse return false;
                if (!global_types.equal(self.graph, payload, target_payload)) return false;
            } else if (matching.variant.payload_type != null) return false;
        }
        return true;
    }

    fn blockContains(self: *Resolver, block_id: global_sg.GlobalBlockId, target: global_sg.GlobalNodeId) bool {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            if (self.nodeContains(node_id, target)) return true;
        }
        return false;
    }

    // A propagation can be nested in any expression, not just in a block's
    // top-level node list. Follow graph edges so its enclosing return type is
    // found without relying on source positions or allocation order.
    fn nodeContains(self: *Resolver, node_id: global_sg.GlobalNodeId, target: global_sg.GlobalNodeId) bool {
        if (node_id == target) return true;
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        return switch (node.content) {
            .move_value, .address_of => |child| self.nodeContains(child, target),
            .assignment => |value| self.nodeContains(value.value, target),
            .function_call => |call| self.nodeContains(call.input, target),
            .virtual_call => |id| blk: {
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                break :blk self.nodeContains(call.handle, target) or self.nodeContains(call.input, target);
            },
            .virtualize => |id| self.nodeContains(self.graph.virtualizes.items[@intFromEnum(id)].value, target),
            .code_block => |child| self.blockContains(child, target),
            .list_literal => |literal| self.nodeRangeContains(literal.elements, target),
            .array_literal => |literal| self.nodeRangeContains(literal.elements, target),
            .struct_value_literal => |literal| blk: {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field|
                    if (self.nodeContains(field.value, target)) break :blk true;
                break :blk false;
            },
            .struct_field_access => |access| self.nodeContains(access.value, target),
            .choice_literal => |literal| if (literal.payload) |child| self.nodeContains(child, target) else false,
            .choice_payload_access => |access| self.nodeContains(access.value, target),
            .nullable_unwrap_or => |id| blk: {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(id)];
                break :blk self.nodeContains(unwrap.nullable_value, target) or self.nodeContains(unwrap.fallback_value, target);
            },
            .testing_expect_error => |id| blk: {
                const value = self.graph.testing_expect_errors.items[@intFromEnum(id)];
                break :blk self.nodeContains(value.actual_result, target) or self.nodeContains(value.expected_reason, target);
            },
            .error_propagation => |id| self.nodeContains(self.graph.error_propagations.items[@intFromEnum(id)].errable_value, target),
            .error_context => |id| blk: {
                const value = self.graph.error_contexts.items[@intFromEnum(id)];
                break :blk self.nodeContains(value.errable_value, target) or self.nodeContains(value.context, target);
            },
            .array_index => |access| self.nodeContains(access.array_ptr, target) or self.nodeContains(access.index, target),
            .array_store => |store| self.nodeContains(store.array_ptr, target) or self.nodeContains(store.index, target) or self.nodeContains(store.value, target),
            .struct_field_store => |store| self.nodeContains(store.struct_ptr, target) or self.nodeContains(store.value, target),
            .binary_operation => |operation| self.nodeContains(operation.left, target) or self.nodeContains(operation.right, target),
            .comparison => |operation| self.nodeContains(operation.left, target) or self.nodeContains(operation.right, target),
            .logical_operation => |operation| self.nodeContains(operation.left, target) or self.nodeContains(operation.right, target),
            .return_statement => |statement| if (statement.expression) |child| self.nodeContains(child, target) else false,
            .if_statement => |statement| self.nodeContains(statement.condition, target) or self.blockContains(statement.then_block, target) or
                (if (statement.else_block) |child| self.blockContains(child, target) else false),
            .while_statement => |statement| self.nodeContains(statement.condition, target) or self.blockContains(statement.body, target),
            .for_statement => |statement| (if (statement.init) |child| self.nodeContains(child, target) else false) or
                self.nodeContains(statement.condition, target) or
                (if (statement.increment) |child| self.nodeContains(child, target) else false) or self.blockContains(statement.body, target),
            .switch_statement => |id| blk: {
                const sw = self.graph.switches.items[@intFromEnum(id)];
                if (self.nodeContains(sw.expression, target)) break :blk true;
                for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len]) |case|
                    if (self.blockContains(case.body, target)) break :blk true;
                break :blk if (sw.default_block) |child| self.blockContains(child, target) else false;
            },
            .dereference => |value| self.nodeContains(value.pointer, target),
            .pointer_assignment => |value| self.nodeContains(value.pointer, target) or self.nodeContains(value.value, target),
            .type_initializer => |value| self.nodeContains(value.args, target),
            .explicit_cast => |value| self.nodeContains(value.value, target),
            else => false,
        };
    }

    fn nodeRangeContains(self: *Resolver, range: primitives.Range(global_sg.GlobalNodeId), target: global_sg.GlobalNodeId) bool {
        for (self.graph.node_refs.items[range.start..][0..range.len]) |child|
            if (self.nodeContains(child, target)) return true;
        return false;
    }

    fn builtin(self: *Resolver, wanted: primitives.BuiltinType) !global_sg.GlobalTypeId {
        for (self.graph.types.items, 0..) |ty, raw| switch (ty) {
            .builtin => |value| if (value == wanted) return @enumFromInt(@as(u32, @intCast(raw))),
            else => {},
        };
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .builtin = wanted });
        return id;
    }
};

fn unwrapSingleField(graph: *const global_sg.GlobalSemanticGraph, ty: global_sg.GlobalTypeId) ?global_sg.GlobalTypeId {
    const fields = global_types.fields(graph, ty) orelse return null;
    if (fields.len != 1) return null;
    return graph.fields.items[fields.start].ty;
}

fn singleFieldIndex(graph: *const global_sg.GlobalSemanticGraph, ty: global_sg.GlobalTypeId) ?u32 {
    const fields = global_types.fields(graph, ty) orelse return null;
    return if (fields.len == 1) 0 else null;
}

test "error propagation resolver writes indexed payloads" {
    try std.testing.expect(@sizeOf(global_sg.GlobalErrorPropagationId) == 4);
    try std.testing.expect(@sizeOf(global_sg.GlobalErrorContextId) == 4);
}

test "enclosing error search follows nested call arguments" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .bool_literal = true } });
    try graph.value_fields.append(allocator, .{ .name = try graph.addString(allocator, "value"), .value = @enumFromInt(0) });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 1 } } } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .function_call = .{ .callee = @enumFromInt(0), .input = @enumFromInt(1) } } });
    try graph.node_refs.append(allocator, @enumFromInt(2));
    try graph.blocks.append(allocator, .{ .nodes = .{ .start = 0, .len = 1 }, .ret_val = null });
    var resolver: Resolver = .{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{},
        .offsets = &.{},
        .core = undefined,
    };
    try std.testing.expect(resolver.blockContains(@enumFromInt(0), @enumFromInt(0)));
}

test "error payload propagation requires a superset of reasons" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.variants.append(allocator, .{ .name = try graph.addString(allocator, "first"), .source = source, .value = 0 });
    try graph.variants.append(allocator, .{ .name = try graph.addString(allocator, "first"), .source = source, .value = 0 });
    try graph.variants.append(allocator, .{ .name = try graph.addString(allocator, "second"), .source = source, .value = 1 });
    try graph.types.append(allocator, .{ .builtin = .UInt8 });
    try graph.types.append(allocator, .{ .structural_choice = .{ .variants = .{ .start = 0, .len = 1 } } });
    try graph.types.append(allocator, .{ .structural_choice = .{ .variants = .{ .start = 1, .len = 2 } } });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "reason"), .ty = @enumFromInt(1), .source = source });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "trace"), .ty = @enumFromInt(0), .source = source });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "reason"), .ty = @enumFromInt(2), .source = source });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "trace"), .ty = @enumFromInt(0), .source = source });
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } });
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 2, .len = 2 } } });
    const resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = undefined };
    try std.testing.expect(resolver.errorPayloadCanPropagate(@enumFromInt(3), @enumFromInt(4)));
    try std.testing.expect(!resolver.errorPayloadCanPropagate(@enumFromInt(4), @enumFromInt(3)));
}
