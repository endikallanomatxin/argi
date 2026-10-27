const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/101X_defer_generic_propagation" {
    try buildExpectFail("tests/feature_tests/errors/101X_defer_generic_propagation", "cannot return or propagate errors from a deferred action");
}
