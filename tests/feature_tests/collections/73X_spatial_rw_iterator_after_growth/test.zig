const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/73X_spatial_rw_iterator_after_growth" {
    try buildExpectFail("tests/feature_tests/collections/73X_spatial_rw_iterator_after_growth", "root that has ended");
}
