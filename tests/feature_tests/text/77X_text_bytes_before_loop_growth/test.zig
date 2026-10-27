const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/77X_text_bytes_before_loop_growth" {
    try expectFrontendFailure("tests/feature_tests/text/77X_text_bytes_before_loop_growth", "ended");
}
