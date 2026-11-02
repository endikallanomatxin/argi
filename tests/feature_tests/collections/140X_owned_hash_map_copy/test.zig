const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/140X_owned_hash_map_copy" {
    try expectFrontendFailure("tests/feature_tests/collections/140X_owned_hash_map_copy", "cannot be copied implicitly");
}
