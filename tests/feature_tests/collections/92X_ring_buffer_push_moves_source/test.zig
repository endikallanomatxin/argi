const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/92X_ring_buffer_push_moves_source" {
    try buildExpectFail("tests/feature_tests/collections/92X_ring_buffer_push_moves_source", "moved and cannot be used");
}
