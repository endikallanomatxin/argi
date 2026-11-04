const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 33X_virtual_access_bound_global" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/33X_virtual_access_bound_global", "access bounds");
}
