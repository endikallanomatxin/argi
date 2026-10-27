const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/89X_ring_buffer_borrow_after_pop" {
    try expectFrontendFailure("tests/feature_tests/collections/89X_ring_buffer_borrow_after_pop", "root that has ended");
}
