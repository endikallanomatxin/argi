const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/294X_external_reference_implementation" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/294X_external_reference_implementation", "must belong to the contract module or a nominal participant module");
}
