const std = @import("std");
const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "argi run forwards program arguments after the separator" {
    const path = "tests/feature_tests/system/91_run_program_arguments";
    const result = try support.runArgiCommand(&.{ "run", path, "--frontend-jobs", "1", "--", "--output", "--emit-llvm", "--vm", "--help", "-v", "", "a b", "--", "á;$(no)" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 7) std.debug.print("run stderr: {s}\n", .{result.stderr});
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 7 }, result.term);
    const empty = try support.runArgiCommand(&.{ "run", path, "--" });
    defer std.testing.allocator.free(empty.stdout);
    defer std.testing.allocator.free(empty.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 7 }, empty.term);
}
