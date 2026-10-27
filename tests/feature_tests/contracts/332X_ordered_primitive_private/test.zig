const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/332X_ordered_primitive_private" {
    try buildExpectFail("tests/feature_tests/contracts/332X_ordered_primitive_private", "no generic function");
}
