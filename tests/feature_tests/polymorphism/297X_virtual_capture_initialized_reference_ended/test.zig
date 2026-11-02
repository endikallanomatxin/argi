const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/297X_virtual_capture_initialized_reference_ended" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/297X_virtual_capture_initialized_reference_ended", "root that has ended");
}
