const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/296X_virtual_capture_old_alias_after_reinitialization" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/296X_virtual_capture_old_alias_after_reinitialization", "root that has ended");
}
