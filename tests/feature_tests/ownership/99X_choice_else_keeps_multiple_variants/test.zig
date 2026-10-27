const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/99X_choice_else_keeps_multiple_variants" {
    try buildExpectFail(
        "tests/feature_tests/ownership/99X_choice_else_keeps_multiple_variants",
        "requires its variant to be proven active",
    );
}
