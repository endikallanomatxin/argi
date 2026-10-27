const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/131X_hash_entry_mutable_key" {
    try buildExpectFail("tests/feature_tests/collections/131X_hash_entry_mutable_key", "read-only");
}
