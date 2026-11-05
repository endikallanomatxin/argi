const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism/375X_nested_region_unknown_member" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/375X_nested_region_unknown_member", "unknown associated region");
}
