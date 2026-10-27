const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/129X_hash_entry_after_remove" {
    try expectFrontendFailure("tests/feature_tests/collections/129X_hash_entry_after_remove", "root that has ended");
}
