const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/162X_virtual_consumes_byvalue" {
    try buildExpectFail("tests/feature_tests/polymorphism/162X_virtual_consumes_byvalue", "consumes requires a mutable reference input");
}
