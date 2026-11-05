const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 365X_region_duplicate_requirement" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/365X_region_duplicate_requirement", "duplicate Contract storage domain");
}
