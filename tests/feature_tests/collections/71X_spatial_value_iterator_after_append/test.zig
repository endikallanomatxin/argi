const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/71X_spatial_value_iterator_after_append" {
    try buildExpectFail("tests/feature_tests/collections/71X_spatial_value_iterator_after_append", "root that has ended");
}
