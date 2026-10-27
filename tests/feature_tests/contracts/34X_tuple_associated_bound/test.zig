const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/34X_tuple_associated_bound" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/34X_tuple_associated_bound", "does not satisfy its declared bound", "panic");
}
