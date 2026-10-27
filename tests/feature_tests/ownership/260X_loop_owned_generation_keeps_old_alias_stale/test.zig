const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/260X_loop_owned_generation_keeps_old_alias_stale" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/260X_loop_owned_generation_keeps_old_alias_stale",
        "reference depends on a root that has ended",
    );
}
