const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/103X_hash_map_borrow_after_cleanup" {
    try buildExpectFail("tests/feature_tests/collections/103X_hash_map_borrow_after_cleanup", "root that has ended");
}
