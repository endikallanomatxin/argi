const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/26X_print_without_system" {
    try buildExpectFailWithoutNoise("tests/feature_tests/io/26X_print_without_system", ".writer uses reach writer", "panic");
}
