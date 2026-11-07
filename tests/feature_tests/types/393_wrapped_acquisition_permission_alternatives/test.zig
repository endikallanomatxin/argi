const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/393_wrapped_acquisition_permission_alternatives" {
    try support.expectSuccessfulBuild("tests/feature_tests/types/393_wrapped_acquisition_permission_alternatives");
    try support.runExpect("tests/feature_tests/types/393_wrapped_acquisition_permission_alternatives", 0);
}
