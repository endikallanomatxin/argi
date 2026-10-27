const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/64X_spatial_view_after_append" {
    try buildExpectFail("tests/feature_tests/collections/64X_spatial_view_after_append", "root that has ended");
}
