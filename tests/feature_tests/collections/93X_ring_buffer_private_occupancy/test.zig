const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/93X_ring_buffer_private_occupancy" {
    try buildExpectFail("tests/feature_tests/collections/93X_ring_buffer_private_occupancy", "field '_head' is private");
}
