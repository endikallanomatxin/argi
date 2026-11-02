const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/44X_uninit_helper_private" {
    try expectFrontendFailure(
        "tests/feature_tests/collections/44X_uninit_helper_private",
        "no function named '_trusted_uninit_slot' exists",
    );
}
