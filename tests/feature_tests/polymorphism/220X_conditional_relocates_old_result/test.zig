const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/220X_conditional_relocates_old_result" {
    try buildExpectFail("tests/feature_tests/polymorphism/220X_conditional_relocates_old_result", "maybe_initialized and cannot be used");
}
