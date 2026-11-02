const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/175X_loop_output_keeps_loan" {
    try expectFrontendFailure("tests/feature_tests/execution/175X_loop_output_keeps_loan", "root that has ended");
}
