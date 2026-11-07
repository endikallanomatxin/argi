const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/389_acquisition_permission_both_returns" {
    try support.expectSuccessfulBuild("tests/feature_tests/types/389_acquisition_permission_both_returns");
    try support.runExpect("tests/feature_tests/types/389_acquisition_permission_both_returns", 0);
}
