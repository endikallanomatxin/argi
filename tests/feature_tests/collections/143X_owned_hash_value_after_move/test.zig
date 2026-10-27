const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/143X_owned_hash_value_after_move" {
    try expectFrontendFailure("tests/feature_tests/collections/143X_owned_hash_value_after_move", "moved");
}
