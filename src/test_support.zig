const std = @import("std");

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
    \\Add<.Left: Type, .Right: Type, .Args: Type>: Contract = (.Result: Type, .add: (.args: Args) -> (.result: Result))
    \\implement Add<Int32, Int32, (.left: Int32, .right: Int32)> (
    \\    .Result: Type = Int32
    \\    .add = (.args: (.left: Int32, .right: Int32)) -> (.result: Result) { result = __scalar_add(.left = args.left, .right = args.right) }
    \\)
    \\Subtract<.Left: Type, .Right: Type, .Args: Type>: Contract = (.Result: Type, .subtract: (.args: Args) -> (.result: Result))
    \\implement Subtract<Int32, Int32, (.left: Int32, .right: Int32)> (
    \\    .Result: Type = Int32
    \\    .subtract = (.args: (.left: Int32, .right: Int32)) -> (.result: Result) { result = __scalar_subtract(.left = args.left, .right = args.right) }
    \\)
    \\Multiply<.Left: Type, .Right: Type, .Args: Type>: Contract = (.Result: Type, .multiply: (.args: Args) -> (.result: Result))
    \\implement Multiply<Int32, Int32, (.left: Int32, .right: Int32)> (
    \\    .Result: Type = Int32
    \\    .multiply = (.args: (.left: Int32, .right: Int32)) -> (.result: Result) { result = __scalar_multiply(.left = args.left, .right = args.right) }
    \\)
    \\Equal<.Left: Type, .Right: Type, .Args: Type>: Contract = (.equal: (.args: Args) -> (.ok: Bool))
    \\_TestEquality<.Value: Type>: Contract = ()
    \\implement _TestEquality<Int32> ()
    \\implement _TestEquality<UInt8> ()
    \\implement<.Value: Type: _TestEquality> Equal<Value, Value, (.left: Value, .right: Value)> (
    \\    .equal = (.args: (.left: Value, .right: Value)) -> (.ok: Bool) { ok = __scalar_equal(.left = args.left, .right = args.right) }
    \\)
    \\CompareRelations<.Left: Type, .Right: Type>: Contract = (
    \\    .less_than: (.left: Left, .right: Right) -> (.ok: Bool)
    \\    .less_than_or_equal: (.left: Left, .right: Right) -> (.ok: Bool)
    \\    .greater_than: (.left: Left, .right: Right) -> (.ok: Bool)
    \\    .greater_than_or_equal: (.left: Left, .right: Right) -> (.ok: Bool)
    \\)
    \\implement<.Value: Type: _TestEquality> CompareRelations<Value, Value> (
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
