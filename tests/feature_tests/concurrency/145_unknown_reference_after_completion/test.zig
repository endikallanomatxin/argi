const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "145_unknown_reference_after_completion" {
    const path = "tests/feature_tests/concurrency/145_unknown_reference_after_completion";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
