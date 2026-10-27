const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/161X_virtual_consumes_readonly" {
    try buildExpectFail("tests/feature_tests/polymorphism/161X_virtual_consumes_readonly", "consumes requires a mutable reference input");
}
