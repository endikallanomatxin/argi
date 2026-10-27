const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/218X_conditional_relocates_moved_source" {
    try buildExpectFail("tests/feature_tests/polymorphism/218X_conditional_relocates_moved_source", "moved and cannot be used");
}
