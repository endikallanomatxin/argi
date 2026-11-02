const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/292X_virtual_capture_before_initialization" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/292X_virtual_capture_before_initialization", "value was deinitialized");
}
