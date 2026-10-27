const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/273X_borrowed_call_keeps_copy_stale" {
    try buildExpectFailWithoutNoise("tests/feature_tests/execution/273X_borrowed_call_keeps_copy_stale", "reference depends on a root that has ended", "failed without a diagnostic");
}
