const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/errors/95X_defer_propagation" {
    try expectFrontendFailure("tests/feature_tests/errors/95X_defer_propagation", "cannot return or propagate errors from a deferred action");
}
