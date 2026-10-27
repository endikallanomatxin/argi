const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/98X_defer_generic_return" {
    try buildExpectFail("tests/feature_tests/errors/98X_defer_generic_return", "cannot return or propagate errors from a deferred action");
}
