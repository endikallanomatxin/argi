const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/100X_main_extra_outputs" {
    try expectFrontendFailure("tests/feature_tests/basics/100X_main_extra_outputs", "main must return no values or (.status_code: Int32)");
}
