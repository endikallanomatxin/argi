const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/224X_conditional_relocates_scope_reference" {
    try buildExpectFail("tests/feature_tests/polymorphism/224X_conditional_relocates_scope_reference", "reference depends on a root that has ended");
}
