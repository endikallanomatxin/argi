const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/103X_hash_map_borrow_after_cleanup" {
    try expectFrontendFailure("tests/feature_tests/collections/103X_hash_map_borrow_after_cleanup", "root that has ended");
}
