const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/73X_virtual_safety_contract_invalidation" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/73X_virtual_safety_contract_invalidation", "storage transition is not permitted by this preservation contract");
}
