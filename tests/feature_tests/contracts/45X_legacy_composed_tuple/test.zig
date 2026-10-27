const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/45X_legacy_composed_tuple" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/45X_legacy_composed_tuple", "a required contract dependency is not satisfied", "panic");
}
