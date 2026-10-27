const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/37X_unicode_scalar_private" {
    try buildExpectFail("tests/feature_tests/text/37X_unicode_scalar_private", "field '_value' is private");
}
