const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/213X_conditional_relocates_ambiguous" {
    try buildExpectFail("tests/feature_tests/polymorphism/213X_conditional_relocates_ambiguous", "cannot select cleanup for conditional relocation");
}
