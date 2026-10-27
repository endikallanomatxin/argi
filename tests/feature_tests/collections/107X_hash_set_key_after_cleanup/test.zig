const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/107X_hash_set_key_after_cleanup" {
    try buildExpectFail("tests/feature_tests/collections/107X_hash_set_key_after_cleanup", "opaque storage hides a dependency");
}
