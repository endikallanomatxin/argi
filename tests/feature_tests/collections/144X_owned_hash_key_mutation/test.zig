const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/144X_owned_hash_key_mutation" {
    try expectFrontendFailure("tests/feature_tests/collections/144X_owned_hash_key_mutation", "read-only");
}
