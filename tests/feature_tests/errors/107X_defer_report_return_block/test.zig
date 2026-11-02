const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/errors/107X_defer_report_return_block" {
    try expectFrontendFailure("tests/feature_tests/errors/107X_defer_report_return_block", "cannot return or propagate errors from a deferred action");
}
