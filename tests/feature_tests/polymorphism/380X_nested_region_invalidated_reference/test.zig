const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "380X_nested_region_invalidated_reference" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/380X_nested_region_invalidated_reference", "root that has ended");
}
