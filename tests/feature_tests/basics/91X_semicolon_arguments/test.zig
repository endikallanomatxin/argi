const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/91X_semicolon_arguments" {
    try buildExpectFailWithoutNoise("tests/feature_tests/basics/91X_semicolon_arguments", "';' separates statements, not arguments, fields, or expression parts", "panic");
}
