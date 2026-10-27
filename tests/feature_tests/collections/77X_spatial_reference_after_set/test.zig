const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/77X_spatial_reference_after_set" {
    try buildExpectFail("tests/feature_tests/collections/77X_spatial_reference_after_set", "root that has ended");
}
