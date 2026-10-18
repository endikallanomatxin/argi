const std = @import("std");
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
    const boolean: ?g.GlobalTypeId = for (graph.types.items, 0..) |ty, index| {
        if (ty == .builtin and ty.builtin == .Bool) break @enumFromInt(index);
    } else null;
    const result = try allocator.alloc(b.SessionBinding, bindings.len);
    for (bindings, result, 0..) |binding, *out, index| {
        if (@intFromEnum(binding) >= graph.bindings.items.len) return error.InvalidSessionBinding;
        if (std.mem.indexOfScalar(g.GlobalBindingId, bindings[0..index], binding) != null) return error.DuplicateSessionBinding;
        const ty = graph.binding(binding).ty;
        const flags = if (required[@intFromEnum(binding)]) try counts.count(allocator, graph, ty) else 0;
        const slot_count = try std.math.add(usize, flags, 1);
        if (slot_count > std.math.maxInt(u32)) return error.InvalidSessionBinding;
        const slots = try allocator.alloc(b.Type, slot_count);
        slots[0] = ty;
        if (flags != 0) @memset(slots[1..], boolean orelse return error.MissingSessionCleanupType);
        const cleanup = try allocator.alloc(b.Cleanup, flags);
        var cursor: usize = 0;
        if (flags != 0) try fill(allocator, graph, ty, &.{}, cleanup, &cursor, 0);
        std.debug.assert(cursor == flags);
        out.* = .{ .binding = binding, .slots = slots, .cleanup = cleanup };
    }
    return result;
}

fn fill(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, path: []const value.Projection, cleanup: []b.Cleanup, cursor: *usize, depth: usize) anyerror!void {
    if (depth > 64 or cursor.* >= cleanup.len) return error.InvalidSessionBinding;
    const index = cursor.*;
    cleanup[index] = .{ .root = 0, .flag = @intCast(index + 1), .path = path };
    cursor.* += 1;
    const children = shape.Shape.of(graph, ty);
    for (0..children.len()) |position| if (children.child(graph, position)) |child| {
        const projected = try allocator.alloc(value.Projection, path.len + 1);
        @memcpy(projected[0..path.len], path);
        projected[path.len] = switch (child.projection) {
            .field => |field| .{ .field = field },
            .variant => |variant| .{ .variant = try b.variantOrdinal(graph, ty, variant) },
        };
        try fill(allocator, graph, child.ty, projected, cleanup, cursor, depth + 1);
    };
}
