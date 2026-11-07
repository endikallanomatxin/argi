const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/384_acquisition_permission_virtual_transfer" {
    try support.expectSuccessfulBuild("tests/feature_tests/types/384_acquisition_permission_virtual_transfer");
    try support.runExpect("tests/feature_tests/types/384_acquisition_permission_virtual_transfer", 0);
}
