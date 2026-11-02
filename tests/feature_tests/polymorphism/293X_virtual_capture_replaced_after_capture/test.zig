const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/293X_virtual_capture_replaced_after_capture" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/293X_virtual_capture_replaced_after_capture", "virtual capture has no proven final post-call generation");
}
