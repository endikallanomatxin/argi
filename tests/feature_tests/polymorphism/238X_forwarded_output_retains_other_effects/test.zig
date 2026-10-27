const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/238X_forwarded_output_retains_other_effects" {
    try buildExpectFail("tests/feature_tests/polymorphism/238X_forwarded_output_retains_other_effects", "reference depends on a root that has ended");
}
