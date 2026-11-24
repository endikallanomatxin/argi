const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/416X_release_after_arena_reset" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/416X_release_after_arena_reset",
        "reference depends on a root that has ended",
    );
}
