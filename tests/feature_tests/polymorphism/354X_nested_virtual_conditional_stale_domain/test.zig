const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 354X_nested_virtual_conditional_stale_domain" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/354X_nested_virtual_conditional_stale_domain", "root that has ended");
}
