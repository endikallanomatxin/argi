const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/65X_process_stream_lifetime" {
    try buildExpectFail("tests/feature_tests/system/65X_process_stream_lifetime", "reference depends on a root that has ended");
}
