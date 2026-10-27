const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/errors/96X_defer_context" {
    try expectFrontendFailure("tests/feature_tests/errors/96X_defer_context", "cannot return or propagate errors from a deferred action");
}
