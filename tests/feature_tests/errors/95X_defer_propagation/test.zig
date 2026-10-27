const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/95X_defer_propagation" {
    try buildExpectFail("tests/feature_tests/errors/95X_defer_propagation", "cannot return or propagate errors from a deferred action");
}
