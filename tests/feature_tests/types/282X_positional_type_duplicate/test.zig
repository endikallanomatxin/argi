const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/282X_positional_type_duplicate" {
    try buildExpectFail("tests/feature_tests/types/282X_positional_type_duplicate", "duplicate generic argument");
}
