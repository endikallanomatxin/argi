const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/errors/89X_handle_partial_recovery" {
    try expectFrontendFailure("tests/feature_tests/errors/89X_handle_partial_recovery", "cannot be used");
}
