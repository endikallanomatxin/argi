const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/163X_virtual_consumes_use_after" {
    try buildExpectFail("tests/feature_tests/polymorphism/163X_virtual_consumes_use_after", "deinitialized");
}
