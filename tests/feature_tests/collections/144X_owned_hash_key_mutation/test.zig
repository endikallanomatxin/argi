const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/144X_owned_hash_key_mutation" {
    try buildExpectFail("tests/feature_tests/collections/144X_owned_hash_key_mutation", "read-only");
}
