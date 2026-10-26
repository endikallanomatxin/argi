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
    var seen = try std.DynamicBitSetUnmanaged.initEmpty(allocator, graph.bindings.items.len);
    defer seen.deinit(allocator);
    var counts: shape.Counts = .{};
    // The command arena retains layout nodes; only the construction index dies.
    defer counts.values.deinit(allocator);
    var result: std.ArrayList(b.SessionBinding) = .empty;
    errdefer result.deinit(allocator);
    for (bindings) |binding| {
        if (@intFromEnum(binding) >= graph.bindings.items.len) return error.InvalidSessionBinding;
        const index = @intFromEnum(binding);
        if (seen.isSet(index)) return error.DuplicateSessionBinding;
        seen.set(index);
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

fn layoutFailures(allocator: std.mem.Allocator) !void {
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    var bindings: [130]g.GlobalBindingId = undefined;
    for (&bindings, 0..) |*binding, index| {
        binding.* = @enumFromInt(index);
        try graph.bindings.append(allocator, .{
            .name = .{ .start = 0, .len = 0 },
            .source = .{ .file_index = 0, .offset = 0 },
            .ty = @enumFromInt(0),
            .mutability = .variable,
        });
    }
    const layout = try build(allocator, &graph, &bindings);
    defer allocator.free(layout);
    try std.testing.expectEqual(bindings.len, layout.len);
    for (layout, bindings) |row, binding| try std.testing.expectEqual(binding, row.binding);
    const duplicate: ?[]const b.SessionBinding = build(allocator, &graph, &.{ bindings[129], bindings[0], bindings[129] }) catch |err| blk: {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.DuplicateSessionBinding, err);
        break :blk null;
    };
    if (duplicate) |unexpected| {
        allocator.free(unexpected);
        return error.TestUnexpectedResult;
    }
    const invalid: ?[]const b.SessionBinding = build(allocator, &graph, &.{@enumFromInt(130)}) catch |err| blk: {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidSessionBinding, err);
        break :blk null;
    };
    if (invalid) |unexpected| {
        allocator.free(unexpected);
        return error.TestUnexpectedResult;
    }
}

test "session layout validates dense identities and releases failed allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, layoutFailures, .{});
}
