const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/363X_conditional_initialization_requires_outcome" {
    try buildExpectFail("tests/feature_tests/ownership/363X_conditional_initialization_requires_outcome", "cannot select cleanup for conditional initialization");
}
