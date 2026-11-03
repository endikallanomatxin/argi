const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "future cleanup ownership cannot be duplicated" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/system/118X_future_implicit_copy", "cannot be copied implicitly", "failed without a diagnostic");
}
