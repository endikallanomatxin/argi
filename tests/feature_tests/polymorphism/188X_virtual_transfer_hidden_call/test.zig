const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/188X_virtual_transfer_hidden_call" {
    try buildExpectFail("tests/feature_tests/polymorphism/188X_virtual_transfer_hidden_call", "cannot prove transfers");
}
