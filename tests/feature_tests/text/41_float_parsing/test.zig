const std = @import("std");
const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/41_float_parsing" {
    const path = "tests/feature_tests/text/41_float_parsing";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "float parsing battery in the VM" {
    // The complete battery includes hundreds of parses and multi-kilobyte inputs.
    // Individual IEEE extremes also run under the default quota in execution/02.
    const result = try support.runArgiCommand(&.{
        "run",                                       "--vm", "--vm-instructions", "64000000", "--vm-value-cells", "4000000",
        "tests/feature_tests/text/41_float_parsing",
    });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0)
        std.debug.print("VM stderr: {s}\n", .{result.stderr});
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}
