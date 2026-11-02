const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/175X_hash_map_copy_uncopyable_policy" {
    try expectFrontendFailure("tests/feature_tests/collections/175X_hash_map_copy_uncopyable_policy", "no function named 'copy' exists");
}
