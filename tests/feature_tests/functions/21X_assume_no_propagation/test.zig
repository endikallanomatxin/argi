const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/21X_assume_no_propagation" {
    try buildExpectFail("tests/feature_tests/functions/21X_assume_no_propagation", "no function named 'take' accepts arguments");
}
