const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 68X_captured_intermediate_retargeted" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/68X_captured_intermediate_retargeted", "cannot establish captured access region identity");
}
