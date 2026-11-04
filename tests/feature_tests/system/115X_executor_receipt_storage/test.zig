const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "executor cannot substitute receiver-owned receipts under preservation" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/system/115X_executor_receipt_storage", "carries_execution", "failed without a diagnostic");
}
