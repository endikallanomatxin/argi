const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/44X_virtual_self_result" {
    try buildExpectFail("tests/feature_tests/polymorphism/44X_virtual_self_result", "the hidden participant cannot appear in a virtual operation result");
}
