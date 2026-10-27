const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/errors/102X_defer_generic_context" {
    try expectFrontendFailure("tests/feature_tests/errors/102X_defer_generic_context", "cannot return or propagate errors from a deferred action");
}
