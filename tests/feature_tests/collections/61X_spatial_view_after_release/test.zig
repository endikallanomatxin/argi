const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/61X_spatial_view_after_release" {
    try buildExpectFail("tests/feature_tests/collections/61X_spatial_view_after_release", "root that has ended");
}
