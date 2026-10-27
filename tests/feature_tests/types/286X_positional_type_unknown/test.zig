const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/286X_positional_type_unknown" {
    try buildExpectFail("tests/feature_tests/types/286X_positional_type_unknown", "unknown generic argument");
}
