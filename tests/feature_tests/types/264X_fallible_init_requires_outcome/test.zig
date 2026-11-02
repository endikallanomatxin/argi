const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/264X_fallible_init_requires_outcome" {
    try expectFrontendFailure(
        "tests/feature_tests/types/264X_fallible_init_requires_outcome",
        "value was deinitialized",
    );
}
