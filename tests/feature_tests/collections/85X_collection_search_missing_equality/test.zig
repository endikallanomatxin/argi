const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/85X_collection_search_missing_equality" {
    try buildExpectFail("tests/feature_tests/collections/85X_collection_search_missing_equality", "no conformance for the qualified operation's participants");
}
