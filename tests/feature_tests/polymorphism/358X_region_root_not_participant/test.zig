const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 358X_region_root_not_participant" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/358X_region_root_not_participant", "Region root must name the contract's participant");
}
