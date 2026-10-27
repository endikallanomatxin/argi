const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/150X_bit_set_view_after_cleanup" {
    try buildExpectFail("tests/feature_tests/collections/150X_bit_set_view_after_cleanup", "root that has ended");
}
