const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/254X_convert_borrowed_escape" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/254X_convert_borrowed_escape", "local storage generation");
}
