const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/204X_auto_deinit_respects_required_live_inputs" {
    try buildExpectFail(
        "tests/feature_tests/ownership/204X_auto_deinit_respects_required_live_inputs",
        "reference depends on a root that has ended",
    );
}
