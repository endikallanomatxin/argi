const std = @import("std");
const support = @import("../../../support.zig");

// Keep the complete modeling pipeline out of the concurrent fixture phase.
pub const isolation: support.Isolation = .exclusive;

test "feature_tests/geometry/01_kernel" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const directory = try support.tmpDirRootPath(&tmp);
    defer allocator.free(directory);
    const compiler = try support.installedArgiPath();
    defer allocator.free(compiler);
    const repository = try support.repoRootPrefix();
    defer allocator.free(repository);
    const fixture = try std.fs.path.join(allocator, &.{ repository, "tests/feature_tests/geometry/01_kernel" });
    defer allocator.free(fixture);
    const name = if (@import("builtin").os.tag == .windows) "kernel.exe" else "kernel";
    const executable = try std.fs.path.join(allocator, &.{ directory, name });
    defer allocator.free(executable);
    // Resolve the installed bundle, independently of working-tree libraries.
    const built = try support.runChildInCwd(&.{ compiler, "build", fixture, "--output", name }, directory);
    defer allocator.free(built.stdout);
    defer allocator.free(built.stderr);
    if (built.term != .exited or built.term.exited != 0) std.debug.print("{s}", .{built.stderr});
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const result = try support.runChildInCwd(&.{executable}, directory);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try std.testing.expectEqualStrings("", result.stderr);
}
