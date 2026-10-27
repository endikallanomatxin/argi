const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/37X_tuple_invisible_operation" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/37X_tuple_invisible_operation", "missing implementation operation", "panic");
}
