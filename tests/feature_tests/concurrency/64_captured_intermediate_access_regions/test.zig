const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 64_captured_intermediate_access_regions" {
    const path = "tests/feature_tests/concurrency/64_captured_intermediate_access_regions";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
