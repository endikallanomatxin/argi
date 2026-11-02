const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/241X_init_once_operation_repeated" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/241X_init_once_operation_repeated", "once function 'acquire' is consumed more than once");
}
