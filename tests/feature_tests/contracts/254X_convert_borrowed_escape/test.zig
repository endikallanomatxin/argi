const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/254X_convert_borrowed_escape" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/254X_convert_borrowed_escape", "local storage generation");
}
