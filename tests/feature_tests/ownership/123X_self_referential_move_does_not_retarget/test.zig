const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/123X_self_referential_move_does_not_retarget" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/123X_self_referential_move_does_not_retarget",
        "place rooted at 'source' is moved and cannot be used",
    );
}
