const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/281X_positional_type_after_named" {
    try buildExpectFail("tests/feature_tests/types/281X_positional_type_after_named", "positional type arguments must appear before named arguments");
}
