const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 100_completed_helper_allows_aliased_inputs" {
    const path = "tests/feature_tests/concurrency/100_completed_helper_allows_aliased_inputs";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
