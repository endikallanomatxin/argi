const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/python/12X_numeric_readonly" {
    try expectFrontendFailure("tests/feature_tests/python/12X_numeric_readonly", "no generic function named 'copy_numeric'");
}
