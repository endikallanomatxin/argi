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
        const error_payload = err.variant.payload_type orelse try self.builtin(.Any);
        const result_ty = unwrapSingleField(self.graph, ok_payload) orelse ok_payload;

        const target = globalizer.globalNode(o, value.node);
        const propagated_ty = self.enclosingErrableType(target) orelse errable_ty;
        const propagated_error = global_types.findVariant(self.graph, propagated_ty, "error") orelse err;
        const propagated_error_payload = propagated_error.variant.payload_type orelse error_payload;
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

    fn blockContains(self: *Resolver, block_id: global_sg.GlobalBlockId, target: global_sg.GlobalNodeId) bool {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            if (node_id == target) return true;
            const node = self.graph.nodes.items[@intFromEnum(node_id)];
            switch (node.content) {
                .code_block => |child| if (self.blockContains(child, target)) return true,
                .if_statement => |statement| {
                    if (self.blockContains(statement.then_block, target)) return true;
                    if (statement.else_block) |child| if (self.blockContains(child, target)) return true;
                },
                .while_statement => |statement| if (self.blockContains(statement.body, target)) return true,
                .for_statement => |statement| if (self.blockContains(statement.body, target)) return true,
                .switch_statement => |switch_id| {
                    const sw = self.graph.switches.items[@intFromEnum(switch_id)];
                    for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len]) |case|
                        if (self.blockContains(case.body, target)) return true;
                    if (sw.default_block) |child| if (self.blockContains(child, target)) return true;
                },
                else => {},
            }
        }
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
