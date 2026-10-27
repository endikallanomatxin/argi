const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/287X_view_reference_escape" {
    try expectFrontendFailure("tests/feature_tests/contracts/287X_view_reference_escape", "local");
}
