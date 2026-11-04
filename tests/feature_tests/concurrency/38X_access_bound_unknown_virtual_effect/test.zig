const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 38X_access_bound_unknown_virtual_effect" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/38X_access_bound_unknown_virtual_effect", "cannot prove access bounds");
}
