const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/50X_buffered_reader_after_storage" {
    try buildExpectFail("tests/feature_tests/io/50X_buffered_reader_after_storage", "ended");
}
