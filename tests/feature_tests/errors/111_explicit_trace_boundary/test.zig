const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;

test "feature_tests/errors/111_explicit_trace_boundary" {
    const directory = "tests/feature_tests/errors/111_explicit_trace_boundary";
    try support.expectSuccessfulBuild(directory);
    try support.runExpect(directory, 0);
    try support.vmExpect(directory, 0, null);
}
