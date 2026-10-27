const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/22X_assume_incompatible_default" {
    try buildExpectFail("tests/feature_tests/functions/22X_assume_incompatible_default", "no function named 'take' accepts arguments");
}
