const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/204X_conditional_consumption_stale_result" {
    try buildExpectFail("tests/feature_tests/polymorphism/204X_conditional_consumption_stale_result", "maybe_initialized");
}
