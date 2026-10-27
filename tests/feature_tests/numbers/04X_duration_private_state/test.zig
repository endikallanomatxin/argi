const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/04X_duration_private_state" {
    try expectFrontendFailure("tests/feature_tests/numbers/04X_duration_private_state", "field '_nanoseconds' is private to its module");
}
