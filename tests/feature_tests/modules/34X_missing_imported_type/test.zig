const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/modules/34X_missing_imported_type" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/modules/34X_missing_imported_type", "module 'dep' has no type named 'Missing'", "no matching function");
}
