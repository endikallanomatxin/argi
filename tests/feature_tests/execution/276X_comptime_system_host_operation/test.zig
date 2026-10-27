const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/276X_comptime_system_host_operation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/execution/276X_comptime_system_host_operation", "host operation that is not enabled for compile-time execution", "failed without a diagnostic");
}
