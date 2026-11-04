const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 19_reference_result_unsupported" {
    const path = "tests/feature_tests/concurrency/19_reference_result_unsupported";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
