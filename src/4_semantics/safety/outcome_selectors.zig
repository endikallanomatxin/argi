const std = @import("std");
const graph_mod = @import("../global/graph.zig");
const types = @import("../global/types.zig");

pub const Selector = struct {
    output_index: u32,
    parent_variants: []const u32 = &.{},
    variant_index: u32,
};

/// Partition a choice only where a contract or forwarded result needs a deeper
/// guard. Shared nested types must not cause exhaustive path enumeration: their
/// unobserved payloads retain the enclosing conservative effect record instead.
pub fn partition(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, output_index: u32, ty: graph_mod.GlobalTypeId, wanted: []const Selector) ![]const Selector {
    var result: std.ArrayList(Selector) = .empty;
    try append(allocator, graph, output_index, ty, &.{}, wanted, &result);
    return result.toOwnedSlice(allocator);
}

fn append(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, output_index: u32, ty: graph_mod.GlobalTypeId, parents: []const u32, wanted: []const Selector, result: *std.ArrayList(Selector)) anyerror!void {
    const variants = types.variants(graph, ty) orelse return;
    for (graph.variants.items[variants.start..][0..variants.len], 0..) |variant, index| {
        var descend = false;
        for (wanted) |selector| {
            if (selector.output_index != output_index or selector.parent_variants.len <= parents.len) continue;
            if (std.mem.eql(u32, selector.parent_variants[0..parents.len], parents) and selector.parent_variants[parents.len] == index) {
                descend = true;
                break;
            }
        }
        if (descend) {
            const child = variant.payload_type orelse return error.InvalidOutcomeSelector;
            if (types.variants(graph, child) == null) return error.InvalidOutcomeSelector;
            const path = try std.mem.concat(allocator, u32, &.{ parents, &.{@intCast(index)} });
            try append(allocator, graph, output_index, child, path, wanted, result);
        } else try result.append(allocator, .{ .output_index = output_index, .parent_variants = parents, .variant_index = @intCast(index) });
    }
}
