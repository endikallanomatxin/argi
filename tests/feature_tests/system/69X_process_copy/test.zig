const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/69X_process_copy" {
    try buildExpectFailWithoutNoise("tests/feature_tests/system/69X_process_copy", "cannot be copied implicitly", "failed without a diagnostic");
}
