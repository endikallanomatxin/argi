const std = @import("std");
const types = @import("../../4_semantics/global/types.zig");
const g = @import("../../4_semantics/global/graph.zig");
const b = @import("bytecode.zig");
const shape = @import("../cleanup_layout.zig");
const value = @import("value.zig");

/// Allocate immutable layouts in the command's compilation arena. Value slot
/// zero and preorder flags describe actual session storage; selecting which
/// bindings need cleanup remains the checked frontend's responsibility.
pub fn build(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, bindings: []const g.GlobalBindingId) ![]const b.SessionBinding {
    const required = try shape.requiredBindings(allocator, graph);
    defer allocator.free(required);
    var counts: shape.Counts = .{};
    defer counts.deinit(allocator);
    var result: std.ArrayList(b.SessionBinding) = .empty;
    errdefer result.deinit(allocator);
    for (bindings, 0..) |binding, index| {
        if (@intFromEnum(binding) >= graph.bindings.items.len) return error.InvalidSessionBinding;
        if (std.mem.indexOfScalar(g.GlobalBindingId, bindings[0..index], binding) != null) return error.DuplicateSessionBinding;
        if (types.staticTypeBinding(graph, binding) != null) continue;
        const ty = graph.binding(binding).ty;
        const flags = if (required[@intFromEnum(binding)]) try counts.count(allocator, graph, ty) else 0;
        const cleanup = try allocator.alloc(b.Cleanup, flags);
        var cursor: usize = 0;
        var flag_cursor: usize = 0;
        if (flags != 0) try fill(allocator, graph, ty, &.{}, cleanup, &cursor, &flag_cursor, 0);
        std.debug.assert(flag_cursor == flags);
        try result.append(allocator, .{ .binding = binding, .ty = ty, .cleanup = cleanup[0..cursor] });
    }
    return result.toOwnedSlice(allocator);
}

fn fill(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, path: []const value.Projection, cleanup: []b.Cleanup, cursor: *usize, flag_cursor: *usize, depth: usize) anyerror!void {
    if (depth > 64 or cursor.* >= cleanup.len) return error.InvalidSessionBinding;
    const index = cursor.*;
    const children = shape.Shape.of(graph, ty);
    const flag = flag_cursor.*;
    flag_cursor.* += 1;
    const presence: ?u32 = if (children == .variants) blk: {
        const slot = flag_cursor.*;
        flag_cursor.* += 1;
        break :blk @intCast(slot);
    } else null;
    cleanup[index] = .{ .root = 0, .flag = @intCast(flag), .presence = presence, .path = path };
    cursor.* += 1;
    for (0..children.len()) |position| if (children.child(graph, position)) |child| {
        const projected = try allocator.alloc(value.Projection, path.len + 1);
        @memcpy(projected[0..path.len], path);
        projected[path.len] = switch (child.projection) {
            .field => |field| .{ .field = field },
            .variant => |variant| .{ .variant = try b.variantOrdinal(graph, ty, variant) },
        };
        try fill(allocator, graph, child.ty, projected, cleanup, cursor, flag_cursor, depth + 1);
    };
}
