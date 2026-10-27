const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/89X_allocation_forged_bounds_literal" {
    try expectFrontendFailure("tests/feature_tests/types/89X_allocation_forged_bounds_literal", "field '_storage_address' is private to its module");
}
