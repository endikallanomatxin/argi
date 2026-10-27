const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/69X_arena_reset_ends_child_domain" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/69X_arena_reset_ends_child_domain",
        "reference depends on a root that has ended",
    );
}
