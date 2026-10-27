const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/170X_map_query_requires_explicit_view" {
    try buildExpectFail("tests/feature_tests/collections/170X_map_query_requires_explicit_view", "no function named 'get_reference'");
}
