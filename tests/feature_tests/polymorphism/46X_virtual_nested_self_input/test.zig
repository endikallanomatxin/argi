const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/46X_virtual_nested_self_input" {
    try buildExpectFail("tests/feature_tests/polymorphism/46X_virtual_nested_self_input", "the hidden participant is only allowed as a direct borrowed receiver");
}
