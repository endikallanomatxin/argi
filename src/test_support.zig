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
