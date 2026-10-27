const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/90X_handle_without_result_value" {
    try buildExpectFail("tests/feature_tests/errors/90X_handle_without_result_value", "handle without a value binding produces Void");
}
