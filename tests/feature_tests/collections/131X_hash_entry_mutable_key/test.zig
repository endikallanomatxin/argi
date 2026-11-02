const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/131X_hash_entry_mutable_key" {
    try expectFrontendFailure("tests/feature_tests/collections/131X_hash_entry_mutable_key", "read-only");
}
