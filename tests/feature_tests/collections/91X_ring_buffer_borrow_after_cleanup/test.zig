const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/91X_ring_buffer_borrow_after_cleanup" {
    try buildExpectFail("tests/feature_tests/collections/91X_ring_buffer_borrow_after_cleanup", "root that has ended");
}
