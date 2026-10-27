const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/276X_opaque_move_out_preserves_external_dependency" {
    try buildExpectFail(
        "tests/feature_tests/ownership/276X_opaque_move_out_preserves_external_dependency",
        "reference depends on a root that has ended",
    );
}
