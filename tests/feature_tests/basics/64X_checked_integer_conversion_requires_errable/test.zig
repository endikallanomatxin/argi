const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/64X_checked_integer_conversion_requires_errable" {
    try buildExpectFail("tests/feature_tests/basics/64X_checked_integer_conversion_requires_errable", "cannot assign a fallible numeric result directly");
}
