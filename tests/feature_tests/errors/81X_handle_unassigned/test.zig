const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/errors/81X_handle_unassigned" {
    try expectFrontendFailure("tests/feature_tests/errors/81X_handle_unassigned", "cannot be used");
}
