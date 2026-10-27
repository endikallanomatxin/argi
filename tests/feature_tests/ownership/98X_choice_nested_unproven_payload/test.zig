const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/98X_choice_nested_unproven_payload" {
    try buildExpectFail(
        "tests/feature_tests/ownership/98X_choice_nested_unproven_payload",
        "requires its variant to be proven active",
    );
}
