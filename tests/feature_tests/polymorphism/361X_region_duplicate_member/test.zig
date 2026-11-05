const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 361X_region_duplicate_member" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/361X_region_duplicate_member", "duplicate implementation region member");
}
