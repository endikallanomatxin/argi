const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/104X_defer_generic_continue" {
    try buildExpectFail("tests/feature_tests/errors/104X_defer_generic_continue", "cannot exit an enclosing loop from a deferred action");
}
