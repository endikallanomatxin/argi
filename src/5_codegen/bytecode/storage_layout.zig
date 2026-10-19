const std = @import("std");
const g = @import("../../4_semantics/global/graph.zig");
const types = @import("../../4_semantics/global/types.zig");

// Siblings occupy contiguous entries. Leaves hold complete checked values;
// only records expose independently initialized fields in the initial layout.
pub const Node = struct { first: u32 = 0, count: u32 = 0, record: bool = false };
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
    const fields = types.fields(graph, ty) orelse return;
    const start = std.math.cast(u32, nodes.items.len) orelse return error.UnsupportedStorageLayout;
    try nodes.appendNTimes(allocator, .{}, fields.len);
    nodes.items[index] = .{ .record = true, .first = start, .count = fields.len };
    for (graph.fields.items[fields.start..][0..fields.len], 0..) |field, offset|
        try populate(allocator, graph, field.ty, nodes, start + @as(u32, @intCast(offset)), depth + 1);
}
