const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/303X_virtual_capture_forwarded_reachable_alias" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/303X_virtual_capture_forwarded_reachable_alias", "aliased");
}
