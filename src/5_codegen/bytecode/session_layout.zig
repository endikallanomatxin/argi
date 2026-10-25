const std = @import("std");
const types = @import("../../4_semantics/global/types.zig");
const g = @import("../../4_semantics/global/graph.zig");
const b = @import("bytecode.zig");
const shape = @import("../cleanup_layout.zig");

/// Allocate immutable layouts in the command's compilation arena. Value slot
/// zero and preorder flags describe actual session storage; selecting which
/// bindings need cleanup remains the checked frontend's responsibility.
pub fn build(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, bindings: []const g.GlobalBindingId) ![]const b.SessionBinding {
    const required = try shape.requiredBindings(allocator, graph);
    defer allocator.free(required);
    var counts: shape.Counts = .{};
    // The command arena retains layout nodes; only the construction index dies.
    defer counts.values.deinit(allocator);
    var result: std.ArrayList(b.SessionBinding) = .empty;
    errdefer result.deinit(allocator);
    for (bindings, 0..) |binding, index| {
        if (@intFromEnum(binding) >= graph.bindings.items.len) return error.InvalidSessionBinding;
        if (std.mem.indexOfScalar(g.GlobalBindingId, bindings[0..index], binding) != null) return error.DuplicateSessionBinding;
        if (types.staticTypeBinding(graph, binding) != null) continue;
        const ty = graph.binding(binding).ty;
        const cleanup: []const b.Cleanup = if (required[@intFromEnum(binding)]) selected: {
            _ = try counts.count(allocator, graph, ty);
            const entries = try allocator.alloc(b.Cleanup, 1);
            entries[0] = .{ .root = 0, .layout = counts.retained(ty) };
            break :selected entries;
        } else &.{};
        try result.append(allocator, .{ .binding = binding, .ty = ty, .cleanup = cleanup });
    }
    return result.toOwnedSlice(allocator);
}
