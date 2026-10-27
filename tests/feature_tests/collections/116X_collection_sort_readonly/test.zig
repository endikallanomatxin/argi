const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/116X_collection_sort_readonly" {
    try buildExpectFail("tests/feature_tests/collections/116X_collection_sort_readonly", "no generic function named 'sort' accepts arguments");
}
