const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/240X_forwarded_output_rewritten" {
    try buildExpectFail("tests/feature_tests/polymorphism/240X_forwarded_output_rewritten", "reference depends on a root that has ended");
}
