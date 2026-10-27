const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/70X_array_store_range" {
    try buildExpectFail("tests/feature_tests/basics/70X_array_store_range", "integer literal 256 does not fit in 'UInt8'");
}
