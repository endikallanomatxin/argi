const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/204X_auto_deinit_respects_required_live_inputs" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/204X_auto_deinit_respects_required_live_inputs",
        "reference depends on a root that has ended",
    );
}
