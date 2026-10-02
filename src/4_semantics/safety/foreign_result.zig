const std = @import("std");
const graph_mod = @import("../global/graph.zig");
const types = @import("../global/types.zig");
const c_abi = @import("../global/c_abi.zig");
const facts = @import("facts.zig");

/// Foreign addresses carry neither a validity root nor a storage acquisition
/// receipt. Preserve that distinction at field projections, using the same
/// tree for concrete checking and symbolic summaries. Numeric sibling fields
/// remain ordinary values. This describes outputs, not retention/free effects
/// of an external implementation, which remain binding obligations.
pub fn value(comptime Value: type, allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) !Value {
    return valueDepth(Value, allocator, graph, ty, 0);
}

fn valueDepth(comptime Value: type, allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, depth: usize) !Value {
    if (depth >= 32) return .{};
    if (graph.semanticType(ty) == .pointer or c_abi.isRawPointer(graph, ty)) return .{ .foreign_storage = true };
    const range = types.fields(graph, ty) orelse return .{};
    const Field = if (Value == facts.ValueFacts) facts.FieldFacts else facts.OutputFieldEffect;
    var fields: std.ArrayList(Field) = .empty;
    for (graph.fields.items[range.start..][0..range.len], 0..) |field, index| {
        const child = try valueDepth(Value, allocator, graph, types.effectiveFieldType(field), depth + 1);
        if (!child.foreign_storage and child.fields.len == 0) continue;
        const stored = try allocator.create(Value);
        stored.* = child;
        try fields.append(allocator, .{ .index = @intCast(index), .value = stored });
    }
    return .{ .fields = try fields.toOwnedSlice(allocator) };
}

test "foreign record outputs preserve concrete and symbolic field provenance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.appendSlice(allocator, &.{
        .{ .builtin = .Int32 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 }, .layout = .c_struct } },
        .{ .structural = .{ .fields = .{ .start = 2, .len = 1 }, .layout = .c_struct } },
    });
    const field: graph_mod.Field = .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 0 } };
    try graph.fields.append(allocator, field);
    var pointer = field;
    pointer.ty = @enumFromInt(1);
    try graph.fields.append(allocator, pointer);
    var nested = field;
    nested.ty = @enumFromInt(2);
    try graph.fields.append(allocator, nested);
    const concrete = try value(facts.ValueFacts, allocator, &graph, @enumFromInt(3));
    const symbolic = try value(facts.ValueEffect, allocator, &graph, @enumFromInt(3));
    try std.testing.expectEqual(@as(usize, 1), concrete.fields.len);
    try std.testing.expectEqual(concrete.fields[0].index, symbolic.fields[0].index);
    const leaf = concrete.fields[0].value.fields[0];
    const effect = symbolic.fields[0].value.fields[0];
    try std.testing.expectEqual(@as(u32, 1), leaf.index);
    try std.testing.expectEqual(leaf.index, effect.index);
    try std.testing.expect(leaf.value.foreign_storage and effect.value.foreign_storage);
    try std.testing.expectEqual(@as(usize, 0), leaf.value.dependencies.len);
    try std.testing.expectEqual(@as(usize, 0), leaf.value.storage_capabilities.len);
    try std.testing.expectEqual(@as(usize, 0), effect.value.fresh_storage_capabilities.len);
}
