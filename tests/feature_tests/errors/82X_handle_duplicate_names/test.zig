const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/82X_handle_duplicate_names" {
    try buildExpectFail("tests/feature_tests/errors/82X_handle_duplicate_names", "must have different names");
}
