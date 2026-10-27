const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/69X_process_copy" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/system/69X_process_copy", "cannot be copied implicitly", "failed without a diagnostic");
}
