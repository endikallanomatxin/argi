const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/69X_system_storage_escape" {
    try buildExpectFailWithoutNoise("tests/feature_tests/system/69X_system_storage_escape", "function output cannot depend on a local storage generation", "failed without a diagnostic");
}
