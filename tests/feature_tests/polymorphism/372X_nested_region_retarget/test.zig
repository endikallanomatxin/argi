const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism/372X_nested_region_retarget" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/372X_nested_region_retarget", "captured access region identity");
}
