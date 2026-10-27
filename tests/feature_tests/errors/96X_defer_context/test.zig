const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/96X_defer_context" {
    try buildExpectFail("tests/feature_tests/errors/96X_defer_context", "cannot return or propagate errors from a deferred action");
}
