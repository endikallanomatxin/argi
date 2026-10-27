const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/159X_virtual_consumes_missing" {
    try buildExpectFail("tests/feature_tests/polymorphism/159X_virtual_consumes_missing", "cannot prove consumes");
}
