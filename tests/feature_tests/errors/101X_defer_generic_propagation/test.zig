const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/errors/101X_defer_generic_propagation" {
    try expectFrontendFailure("tests/feature_tests/errors/101X_defer_generic_propagation", "cannot return or propagate errors from a deferred action");
}
