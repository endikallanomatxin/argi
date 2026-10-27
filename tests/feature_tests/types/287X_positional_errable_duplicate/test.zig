const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/287X_positional_errable_duplicate" {
    try buildExpectFail("tests/feature_tests/types/287X_positional_errable_duplicate", "duplicate generic argument");
}
