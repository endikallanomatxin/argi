const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/87X_allocation_private_bounds" {
    try expectFrontendFailure("tests/feature_tests/types/87X_allocation_private_bounds", "field '_storage_size' is private to its module");
}
