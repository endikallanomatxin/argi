const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/75X_spatial_iterator_private_fields" {
    try buildExpectFail("tests/feature_tests/collections/75X_spatial_iterator_private_fields", "field '_index' is private");
}
