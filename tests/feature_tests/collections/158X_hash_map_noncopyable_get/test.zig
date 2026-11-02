const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/158X_hash_map_noncopyable_get" {
    try expectFrontendFailure("tests/feature_tests/collections/158X_hash_map_noncopyable_get", "no generic function named 'get' accepts arguments");
}
