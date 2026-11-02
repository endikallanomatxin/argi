const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/192X_init_reference_escape" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/192X_init_reference_escape", "function output cannot depend on a local storage generation");
}
