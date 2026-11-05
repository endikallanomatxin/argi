const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 97_concurrent_disjoint_helper_inputs" {
    const path = "tests/feature_tests/concurrency/97_concurrent_disjoint_helper_inputs";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
