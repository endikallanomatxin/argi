const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/348X_bound_operation_signature" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/348X_bound_operation_signature", "the selected input signature does not match the generic operation alias", "without a diagnostic");
}
