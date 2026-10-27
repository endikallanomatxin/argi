const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/160X_virtual_consumes_conditional_body" {
    try buildExpectFail("tests/feature_tests/polymorphism/160X_virtual_consumes_conditional_body", "cannot prove consumes");
}
