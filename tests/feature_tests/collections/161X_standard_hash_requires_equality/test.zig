const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/161X_standard_hash_requires_equality" {
    try buildExpectFail("tests/feature_tests/collections/161X_standard_hash_requires_equality", "a required contract dependency is not satisfied");
}
