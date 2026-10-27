const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/93X_ring_buffer_private_occupancy" {
    try expectFrontendFailure("tests/feature_tests/collections/93X_ring_buffer_private_occupancy", "field '_head' is private");
}
