const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/99X_defer_generic_report_return" {
    try buildExpectFail("tests/feature_tests/errors/99X_defer_generic_report_return", "cannot return or propagate errors from a deferred action");
}
