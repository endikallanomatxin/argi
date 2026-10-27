const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/95X_choice_unproven_payload" {
    try buildExpectFail(
        "tests/feature_tests/ownership/95X_choice_unproven_payload",
        "requires its variant to be proven active",
    );
}
