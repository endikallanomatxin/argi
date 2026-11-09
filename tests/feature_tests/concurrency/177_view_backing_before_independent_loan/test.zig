const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "177_view_backing_before_independent_loan" {
    const path = "tests/feature_tests/concurrency/177_view_backing_before_independent_loan";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
