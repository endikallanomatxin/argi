const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/194X_init_scalar_arguments" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/194X_init_scalar_arguments", "contract operation input must be a record type");
}
