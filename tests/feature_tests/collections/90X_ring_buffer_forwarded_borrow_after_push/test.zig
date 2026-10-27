const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/90X_ring_buffer_forwarded_borrow_after_push" {
    try expectFrontendFailure("tests/feature_tests/collections/90X_ring_buffer_forwarded_borrow_after_push", "root that has ended");
}
