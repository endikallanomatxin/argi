const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/49X_general_purpose_large_on_arena_reset_live" {
    try expectFrontendFailure(
        "tests/feature_tests/system/49X_general_purpose_large_on_arena_reset_live",
        "reference depends on a root that has ended",
    );
}
