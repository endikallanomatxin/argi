const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/49_release_ir_optimization" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try support.tmpDirRootPath(&tmp);
    defer allocator.free(root);
    const fixture = "tests/feature_tests/basics/49_release_ir_optimization";
    const debug_ir = try std.fs.path.join(allocator, &.{ root, "debug.ll" });
    defer allocator.free(debug_ir);
    const release_ir = try std.fs.path.join(allocator, &.{ root, "release.ll" });
    defer allocator.free(release_ir);
    try support.expectArgiBuildSuccess(&.{ "build", fixture, "--emit-llvm", debug_ir });
    try support.runExpect(fixture, 0);
    try support.expectArgiBuildSuccess(&.{ "build", fixture, "--release", "--emit-llvm", release_ir });
    try support.runExpect(fixture, 0);
    const before = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, debug_ir, allocator, .limited(1024 * 1024));
    defer allocator.free(before);
    const after = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, release_ir, allocator, .limited(1024 * 1024));
    defer allocator.free(after);
    try std.testing.expect(std.mem.count(u8, before, "alloca ") > std.mem.count(u8, after, "alloca "));
    try std.testing.expect(std.mem.count(u8, before, "store i32 ") > std.mem.count(u8, after, "store i32 "));
}
