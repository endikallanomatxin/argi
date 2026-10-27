const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/77X_text_bytes_before_loop_growth" {
    try buildExpectFail("tests/feature_tests/text/77X_text_bytes_before_loop_growth", "ended");
}
