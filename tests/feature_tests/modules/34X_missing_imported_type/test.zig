const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/34X_missing_imported_type" {
    try buildExpectFailWithoutNoise("tests/feature_tests/modules/34X_missing_imported_type", "module 'dep' has no type named 'Missing'", "no matching function");
}
