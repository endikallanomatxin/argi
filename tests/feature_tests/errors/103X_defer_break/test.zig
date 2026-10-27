const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/103X_defer_break" {
    try buildExpectFail("tests/feature_tests/errors/103X_defer_break", "cannot exit an enclosing loop from a deferred action");
}
