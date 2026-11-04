const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 54_distinct_captured_access_regions" {
    const path = "tests/feature_tests/concurrency/54_distinct_captured_access_regions";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
