const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/128X_hash_iterator_after_put" {
    try buildExpectFail("tests/feature_tests/collections/128X_hash_iterator_after_put", "root that has ended");
}
