const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/45X_missing_composed_dependency" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/45X_missing_composed_dependency", "a required contract dependency is not satisfied", "panic");
}
