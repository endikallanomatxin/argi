const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/223X_conditional_relocates_shared_source" {
    try buildExpectFail("tests/feature_tests/polymorphism/223X_conditional_relocates_shared_source", "alias the same storage");
}
