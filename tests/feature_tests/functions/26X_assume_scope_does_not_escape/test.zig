const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/26X_assume_scope_does_not_escape" {
    try buildExpectFail("tests/feature_tests/functions/26X_assume_scope_does_not_escape", "no function named 'take' accepts arguments");
}
