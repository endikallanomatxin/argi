const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/errors/97X_defer_report_return" {
    try expectFrontendFailure("tests/feature_tests/errors/97X_defer_report_return", "cannot return or propagate errors from a deferred action");
}
