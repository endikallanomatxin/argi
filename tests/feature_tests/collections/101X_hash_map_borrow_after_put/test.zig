const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/101X_hash_map_borrow_after_put" {
    try expectFrontendFailure("tests/feature_tests/collections/101X_hash_map_borrow_after_put", "root that has ended");
}
