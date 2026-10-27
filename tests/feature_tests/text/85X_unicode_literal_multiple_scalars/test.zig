const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/85X_unicode_literal_multiple_scalars" {
    try buildExpectFail("tests/feature_tests/text/85X_unicode_literal_multiple_scalars", "exactly one Unicode scalar");
}
