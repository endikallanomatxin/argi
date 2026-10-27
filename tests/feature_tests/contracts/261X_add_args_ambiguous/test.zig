const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/261X_add_args_ambiguous" {
    try buildExpectFail("tests/feature_tests/contracts/261X_add_args_ambiguous", "ambiguous conformances for the same participant tuple");
}
