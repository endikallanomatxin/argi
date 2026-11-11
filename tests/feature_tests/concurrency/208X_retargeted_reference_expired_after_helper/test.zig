const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "208X_retargeted_reference_expired_after_helper" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/208X_retargeted_reference_expired_after_helper", "root that has ended");
}
