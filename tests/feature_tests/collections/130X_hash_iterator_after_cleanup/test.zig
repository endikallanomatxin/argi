const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/130X_hash_iterator_after_cleanup" {
    try buildExpectFail("tests/feature_tests/collections/130X_hash_iterator_after_cleanup", "root that has ended");
}
