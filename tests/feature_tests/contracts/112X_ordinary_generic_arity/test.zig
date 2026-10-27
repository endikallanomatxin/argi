const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/112X_ordinary_generic_arity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/112X_ordinary_generic_arity", "ordinary function 'identity' has more than one declaration", "panic");
}
