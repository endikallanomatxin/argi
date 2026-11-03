const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "executor cannot alter authenticated worker buffer layout" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/system/113X_executor_request_layout", "private", "failed without a diagnostic");
}
