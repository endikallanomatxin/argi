const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/102X_hash_map_borrow_after_remove" {
    try expectFrontendFailure("tests/feature_tests/collections/102X_hash_map_borrow_after_remove", "root that has ended");
}
