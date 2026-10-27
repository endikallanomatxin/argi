const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/33X_dynamic_array_retains_external_borrow" {
    try expectFrontendFailure(
        "tests/feature_tests/collections/33X_dynamic_array_retains_external_borrow",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
