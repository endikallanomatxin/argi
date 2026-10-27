const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/errors/90X_handle_without_result_value" {
    try expectFrontendFailure("tests/feature_tests/errors/90X_handle_without_result_value", "handle without a value binding produces Void");
}
