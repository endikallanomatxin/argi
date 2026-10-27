const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/283X_positional_type_excess" {
    try buildExpectFail("tests/feature_tests/types/283X_positional_type_excess", "too many generic arguments");
}
