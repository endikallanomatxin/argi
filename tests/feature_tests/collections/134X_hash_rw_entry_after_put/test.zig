const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/134X_hash_rw_entry_after_put" {
    try buildExpectFail("tests/feature_tests/collections/134X_hash_rw_entry_after_put", "root that has ended");
}
