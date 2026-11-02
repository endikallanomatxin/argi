const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/107X_hash_set_key_after_cleanup" {
    try expectFrontendFailure("tests/feature_tests/collections/107X_hash_set_key_after_cleanup", "opaque storage hides a dependency");
}
