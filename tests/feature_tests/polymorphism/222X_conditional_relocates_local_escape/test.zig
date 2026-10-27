const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/222X_conditional_relocates_local_escape" {
    try buildExpectFail("tests/feature_tests/polymorphism/222X_conditional_relocates_local_escape", "local storage generation");
}
