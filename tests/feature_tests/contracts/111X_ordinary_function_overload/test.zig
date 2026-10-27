const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/111X_ordinary_function_overload" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/111X_ordinary_function_overload", "ordinary function 'read' has more than one declaration", "panic");
}
