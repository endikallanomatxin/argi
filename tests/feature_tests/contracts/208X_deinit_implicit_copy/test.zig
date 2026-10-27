const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/208X_deinit_implicit_copy" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/208X_deinit_implicit_copy", "cannot be copied implicitly");
}
