const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/298X_virtual_capture_aliased_later_destination" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/298X_virtual_capture_aliased_later_destination", "aliased");
}
