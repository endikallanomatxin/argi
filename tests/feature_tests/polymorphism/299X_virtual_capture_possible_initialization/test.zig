const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/299X_virtual_capture_possible_initialization" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/299X_virtual_capture_possible_initialization", "deinitialized");
}
