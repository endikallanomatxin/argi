const std = @import("std");
const g = @import("../../4_semantics/global/graph.zig");
const types = @import("../../4_semantics/global/types.zig");

// Siblings occupy contiguous template entries. Arrays retain one element
// template, independent of their length. Spans describe concrete execution
// cells; offsets locate record children without expanding repeated shapes.
// Empty aggregates require explicit initialization.
pub const Node = struct {
    first: u32 = 0,
    count: u32 = 0,
    span: u32 = 1,
    offset: u32 = 0,
    kind: enum { leaf, record, array } = .leaf,
};
pub const Layout = struct { nodes: []const Node };

pub fn compile(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId) !Layout {
    var nodes: std.ArrayList(Node) = .empty;
    errdefer nodes.deinit(allocator);
    try nodes.append(allocator, .{});
    try populate(allocator, graph, ty, &nodes, 0, 0);
    return .{ .nodes = try nodes.toOwnedSlice(allocator) };
}
fn populate(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, nodes: *std.ArrayList(Node), index: u32, depth: usize) anyerror!void {
    if (depth > 64) return error.UnsupportedStorageLayout;
    if (types.arrayElement(graph, ty)) |element| {
        const count = std.math.cast(u32, types.arrayLength(graph, ty) orelse return error.UnsupportedStorageLayout) orelse return error.UnsupportedStorageLayout;
        if (count == 0) {
            nodes.items[index].kind = .array;
            return;
        }
        const start = std.math.cast(u32, nodes.items.len) orelse return error.UnsupportedStorageLayout;
        try nodes.append(allocator, .{ .offset = 1 });
        try populate(allocator, graph, element, nodes, start, depth + 1);
        const span = std.math.add(u32, 1, std.math.mul(u32, count, nodes.items[start].span) catch return error.UnsupportedStorageLayout) catch return error.UnsupportedStorageLayout;
        nodes.items[index] = .{ .kind = .array, .first = start, .count = count, .span = span, .offset = nodes.items[index].offset };
        return;
    }
    const fields = types.fields(graph, ty) orelse return;
    if (fields.len == 0) return;
    const start = std.math.cast(u32, nodes.items.len) orelse return error.UnsupportedStorageLayout;
    try nodes.appendNTimes(allocator, .{}, fields.len);
    var span: u32 = 1;
    for (graph.fields.items[fields.start..][0..fields.len], 0..) |field, offset| {
        const child = start + @as(u32, @intCast(offset));
        nodes.items[child].offset = span;
        try populate(allocator, graph, field.ty, nodes, child, depth + 1);
        span = std.math.add(u32, span, nodes.items[child].span) catch return error.UnsupportedStorageLayout;
    }
    nodes.items[index] = .{ .kind = .record, .first = start, .count = fields.len, .span = span, .offset = nodes.items[index].offset };
}
