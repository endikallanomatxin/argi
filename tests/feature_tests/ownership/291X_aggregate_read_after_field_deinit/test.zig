const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/291X_aggregate_read_after_field_deinit" {
    try buildExpectFail(
        "tests/feature_tests/ownership/291X_aggregate_read_after_field_deinit",
        "value was deinitialized",
    );
}
