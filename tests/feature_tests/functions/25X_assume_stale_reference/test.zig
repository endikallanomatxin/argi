const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/25X_assume_stale_reference" {
    try expectFrontendFailure("tests/feature_tests/functions/25X_assume_stale_reference", "reference depends on a root that has ended");
}
