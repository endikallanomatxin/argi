const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/288X_positional_errable_excess" {
    try buildExpectFail("tests/feature_tests/types/288X_positional_errable_excess", "too many generic arguments");
}
