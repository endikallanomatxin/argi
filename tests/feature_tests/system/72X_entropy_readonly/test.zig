const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/72X_entropy_readonly" {
    try expectFrontendFailure("tests/feature_tests/system/72X_entropy_readonly", "no function named 'fill_random_bytes' accepts arguments");
}
