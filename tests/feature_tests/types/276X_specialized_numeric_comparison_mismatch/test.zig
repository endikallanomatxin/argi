const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/276X_specialized_numeric_comparison_mismatch" {
    try buildExpectFail("tests/feature_tests/types/276X_specialized_numeric_comparison_mismatch", "no conformance for the qualified operation's participants");
}
