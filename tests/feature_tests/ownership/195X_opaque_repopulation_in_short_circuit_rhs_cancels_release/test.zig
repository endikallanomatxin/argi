const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/195X_opaque_repopulation_in_short_circuit_rhs_cancels_release" {
    try buildExpectFail(
        "tests/feature_tests/ownership/195X_opaque_repopulation_in_short_circuit_rhs_cancels_release",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
