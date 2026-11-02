const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/116X_collection_sort_readonly" {
    try expectFrontendFailure("tests/feature_tests/collections/116X_collection_sort_readonly", "no generic function named 'sort' accepts arguments");
}
