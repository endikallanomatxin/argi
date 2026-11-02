const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/291X_aggregate_read_after_field_deinit" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/291X_aggregate_read_after_field_deinit",
        "value was deinitialized",
    );
}
