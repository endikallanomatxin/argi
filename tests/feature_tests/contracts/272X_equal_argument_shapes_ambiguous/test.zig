const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/272X_equal_argument_shapes_ambiguous" {
    try buildExpectFail("tests/feature_tests/contracts/272X_equal_argument_shapes_ambiguous", "ambiguous conformances for the same participant tuple");
}
