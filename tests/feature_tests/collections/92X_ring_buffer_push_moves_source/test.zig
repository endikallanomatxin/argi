const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/92X_ring_buffer_push_moves_source" {
    try expectFrontendFailure("tests/feature_tests/collections/92X_ring_buffer_push_moves_source", "moved and cannot be used");
}
