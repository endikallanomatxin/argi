const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/266X_direct_fallible_init_error_leaves_empty" {
    try expectFrontendFailure(
        "tests/feature_tests/types/266X_direct_fallible_init_error_leaves_empty",
        "value was deinitialized",
    );
}
