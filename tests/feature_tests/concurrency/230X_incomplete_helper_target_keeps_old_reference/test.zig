const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "230X_incomplete_helper_target_keeps_old_reference" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/230X_incomplete_helper_target_keeps_old_reference", "root that has ended");
}
