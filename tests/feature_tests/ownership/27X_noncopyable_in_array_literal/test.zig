const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/27X_noncopyable_in_array_literal" {
    try buildExpectFail("tests/feature_tests/ownership/27X_noncopyable_in_array_literal", "type 'Resource' cannot be copied implicitly");
}
