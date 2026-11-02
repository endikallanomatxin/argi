const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/176X_hash_map_copy_uncopyable_value" {
    try expectFrontendFailure("tests/feature_tests/collections/176X_hash_map_copy_uncopyable_value", "no function named 'copy' exists");
}
