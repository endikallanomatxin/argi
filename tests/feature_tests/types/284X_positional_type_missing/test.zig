const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/284X_positional_type_missing" {
    try buildExpectFail("tests/feature_tests/types/284X_positional_type_missing", "missing required generic argument");
}
