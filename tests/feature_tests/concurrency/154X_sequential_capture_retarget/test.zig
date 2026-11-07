const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 154X_sequential_capture_retarget" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/154X_sequential_capture_retarget", "cannot establish captured access region identity");
}
