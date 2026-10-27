const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/59X_spatial_view_after_pop" {
    try buildExpectFail("tests/feature_tests/collections/59X_spatial_view_after_pop", "root that has ended");
}
