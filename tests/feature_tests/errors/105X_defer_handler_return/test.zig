const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/errors/105X_defer_handler_return" {
    try expectFrontendFailure("tests/feature_tests/errors/105X_defer_handler_return", "cannot return or propagate errors from a deferred action");
}
