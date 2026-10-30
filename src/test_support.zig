const std = @import("std");

/// Sweep allocation failures plus every successful-path resize boundary.
/// Resize refusal may recover by allocating; both outcomes must release backing.
pub fn checkAllocationAndResizeFailures(backing: std.mem.Allocator, comptime test_fn: anytype, args: anytype) !void {
    try std.testing.checkAllAllocationFailures(backing, test_fn, args);
    var baseline = std.testing.FailingAllocator.init(backing, .{});
    try @call(.auto, test_fn, .{baseline.allocator()} ++ args);
    try std.testing.expectEqual(baseline.allocated_bytes, baseline.freed_bytes);
    for (0..baseline.resize_index) |index| {
        var failing = std.testing.FailingAllocator.init(backing, .{ .resize_fail_index = index });
        @call(.auto, test_fn, .{failing.allocator()} ++ args) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
        };
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}

/// Independent index ranges permit an expensive sweep to finish in bounded
/// runs. Cover [0, max(allocation_count, resize_count)) before claiming a full
/// sweep. Counts come from the same successful baseline in every run.
pub fn checkAllocationAndResizeFailureRange(backing: std.mem.Allocator, comptime test_fn: anytype, args: anytype, start: usize, end: usize) !void {
    if (start >= end) return error.InvalidFailureRange;
    var baseline = std.testing.FailingAllocator.init(backing, .{});
    try @call(.auto, test_fn, .{baseline.allocator()} ++ args);
    try std.testing.expectEqual(baseline.allocated_bytes, baseline.freed_bytes);
    std.debug.print("failure sweep [{d}, {d}): {d} allocations, {d} resizes\n", .{ start, end, baseline.alloc_index, baseline.resize_index });
    for ([_]bool{ false, true }) |resize| {
        const limit = if (resize) baseline.resize_index else baseline.alloc_index;
        if (start >= limit) continue;
        for (start..@min(end, limit)) |index| {
            if (index % 1000 == 0) std.debug.print("failure sweep {s} index {d}\n", .{ if (resize) "resize" else "allocation", index });
            var failing = std.testing.FailingAllocator.init(backing, if (resize) .{ .resize_fail_index = index } else .{ .fail_index = index });
            if (@call(.auto, test_fn, .{failing.allocator()} ++ args)) |_| {
                if (!resize and failing.has_induced_failure) return error.SwallowedOutOfMemoryError;
            } else |err| {
                try std.testing.expectEqual(error.OutOfMemory, err);
            }
            if (failing.allocated_bytes != failing.freed_bytes) {
                std.debug.print("failure sweep leaked at {s} index {d}: allocated {d}, freed {d}\n", .{ if (resize) "resize" else "allocation", index, failing.allocated_bytes, failing.freed_bytes });
                return error.TestExpectedEqual;
            }
            if (!resize and !failing.has_induced_failure) return error.NondeterministicMemoryUsage;
        }
    }
}

test "allocation failure ranges cover independent positions without hiding recovery" {
    const Probe = struct {
        fn run(a: std.mem.Allocator, seen: *[2]bool) !void {
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(a.ptr));
            if (failing.fail_index < seen.len) seen[failing.fail_index] = true;
            const first = try a.alloc(u8, 8);
            defer a.free(first);
            const second = try a.alloc(u8, 16);
            defer a.free(second);
        }
        fn swallowed(a: std.mem.Allocator) !void {
            const bytes = a.alloc(u8, 8) catch return;
            a.free(bytes);
        }
        fn resizeFallback(a: std.mem.Allocator) !void {
            var bytes = try a.alloc(u8, 8192);
            defer a.free(bytes);
            if (a.resize(bytes, 4096)) bytes = bytes[0..4096];
        }
    };
    var seen = [_]bool{ false, false };
    try checkAllocationAndResizeFailureRange(std.testing.allocator, Probe.run, .{&seen}, 1, 2);
    try std.testing.expectEqualDeep([_]bool{ false, true }, seen);
    try checkAllocationAndResizeFailureRange(std.testing.allocator, Probe.run, .{&seen}, 0, 1);
    try std.testing.expectEqualDeep([_]bool{ true, true }, seen);
    try std.testing.expectError(error.SwallowedOutOfMemoryError, checkAllocationAndResizeFailureRange(std.testing.allocator, Probe.swallowed, .{}, 0, 1));
    try checkAllocationAndResizeFailureRange(std.heap.page_allocator, Probe.resizeFallback, .{}, 0, 2);
    try std.testing.expectError(error.InvalidFailureRange, checkAllocationAndResizeFailureRange(std.testing.allocator, Probe.run, .{&seen}, 2, 2));
}

pub fn tmpRootPath(tmp: *const std.testing.TmpDir) ![:0]u8 {
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(std.testing.io, &buffer);
    return std.testing.allocator.dupeZ(u8, buffer[0..n]);
}

pub fn tmpFilePath(tmp: *const std.testing.TmpDir, rel_path: []const u8) ![:0]u8 {
    return tmp.dir.realPathFileAlloc(std.testing.io, rel_path, std.testing.allocator);
}

/// A small explicit prelude for compiler tests that do not load installed core.
pub const arithmetic_core_source =
    \\Add#(.Left: Type, .Right: Type): Contract = (.Result: Type, .add: _)
    \\implement Add#(Int32, Int32) (
    \\    .Result: Type = Int32
    \\    .add = (.left: Int32, .right: Int32) -> (.result: Result) { result = __scalar_add(.left = left, .right = right) }
    \\)
    \\Subtract#(.Left: Type, .Right: Type): Contract = (.Result: Type, .subtract: _)
    \\implement Subtract#(Int32, Int32) (
    \\    .Result: Type = Int32
    \\    .subtract = (.left: Int32, .right: Int32) -> (.result: Result) { result = __scalar_subtract(.left = left, .right = right) }
    \\)
    \\Multiply#(.Left: Type, .Right: Type): Contract = (.Result: Type, .multiply: _)
    \\implement Multiply#(Int32, Int32) (
    \\    .Result: Type = Int32
    \\    .multiply = (.left: Int32, .right: Int32) -> (.result: Result) { result = __scalar_multiply(.left = left, .right = right) }
    \\)
    \\Equal#(.Left: Type, .Right: Type): Contract = (.equal: (.left: Left, .right: Right) -> (.ok: Bool))
    \\_TestEquality#(.Value: Type): Contract = ()
    \\implement _TestEquality#(Int32) ()
    \\implement _TestEquality#(UInt8) ()
    \\implement#(.Value: Type: _TestEquality) Equal#(Value, Value) (
    \\    .equal = (.left: Value, .right: Value) -> (.ok: Bool) { ok = __scalar_equal(.left = left, .right = right) }
    \\)
    \\CompareRelations#(.Left: Type, .Right: Type): Contract = (
    \\    .less_than: (.left: Left, .right: Right) -> (.ok: Bool)
    \\    .less_than_or_equal: (.left: Left, .right: Right) -> (.ok: Bool)
    \\    .greater_than: (.left: Left, .right: Right) -> (.ok: Bool)
    \\    .greater_than_or_equal: (.left: Left, .right: Right) -> (.ok: Bool)
    \\)
    \\implement#(.Value: Type: _TestEquality) CompareRelations#(Value, Value) (
    \\    .less_than = (.left: Value, .right: Value) -> (.ok: Bool) { ok = __scalar_less_than(.left = left, .right = right) }
    \\    .less_than_or_equal = (.left: Value, .right: Value) -> (.ok: Bool) { ok = __scalar_less_than_or_equal(.left = left, .right = right) }
    \\    .greater_than = (.left: Value, .right: Value) -> (.ok: Bool) { ok = __scalar_greater_than(.left = left, .right = right) }
    \\    .greater_than_or_equal = (.left: Value, .right: Value) -> (.ok: Bool) { ok = __scalar_greater_than_or_equal(.left = left, .right = right) }
    \\)
;

pub const cleanup_layouts = struct {
    const Layout = @import("5_codegen/cleanup_layout.zig").Layout;
    pub const leaf: Layout = .{};
    pub const single: Layout = .{ .count = 2, .is_record = true, .children = &.{.{ .offset = 1, .ty = @enumFromInt(0), .layout = &leaf }} };
    pub const pair: Layout = .{ .count = 3, .is_record = true, .children = &.{ .{ .offset = 1, .ty = @enumFromInt(0), .layout = &leaf }, .{ .offset = 2, .ty = @enumFromInt(0), .layout = &leaf } } };
    pub const nested: Layout = .{ .count = 4, .is_record = true, .children = &.{ .{ .offset = 1, .ty = @enumFromInt(0), .layout = &single }, .{ .offset = 3, .ty = @enumFromInt(0), .layout = &leaf } } };
    pub const choice: Layout = .{ .count = 3, .is_choice = true, .children = &.{.{ .offset = 2, .ty = @enumFromInt(0), .layout = &leaf }} };
};
