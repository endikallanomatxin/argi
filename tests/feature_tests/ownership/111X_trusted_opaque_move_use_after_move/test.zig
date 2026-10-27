const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/111X_trusted_opaque_move_use_after_move" {
    try buildExpectFail("tests/feature_tests/ownership/111X_trusted_opaque_move_use_after_move", "binding 'value' was moved and cannot be used again");
}
