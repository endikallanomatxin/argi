const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/binary/03X_cursor_after_storage" {
    try buildExpectFail("tests/feature_tests/binary/03X_cursor_after_storage", "root that has ended");
}
