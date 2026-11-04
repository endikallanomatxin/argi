const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 55_grouped_captured_access_domain" {
    const path = "tests/feature_tests/concurrency/55_grouped_captured_access_domain";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
