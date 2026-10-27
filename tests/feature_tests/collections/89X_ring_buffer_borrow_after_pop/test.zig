const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/89X_ring_buffer_borrow_after_pop" {
    try buildExpectFail("tests/feature_tests/collections/89X_ring_buffer_borrow_after_pop", "root that has ended");
}
