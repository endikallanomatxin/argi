const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/81X_handle_unassigned" {
    try buildExpectFail("tests/feature_tests/errors/81X_handle_unassigned", "cannot be used");
}
