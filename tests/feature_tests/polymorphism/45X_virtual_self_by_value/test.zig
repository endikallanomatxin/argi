const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/45X_virtual_self_by_value" {
    try buildExpectFail("tests/feature_tests/polymorphism/45X_virtual_self_by_value", "the hidden participant is only allowed as a direct borrowed receiver");
}
