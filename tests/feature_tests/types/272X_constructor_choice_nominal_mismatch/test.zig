const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/272X_constructor_choice_nominal_mismatch" {
    try buildExpectFail("tests/feature_tests/types/272X_constructor_choice_nominal_mismatch", "no function named 'FirstWrapper'");
}
