const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/221X_virtual_contract_rejects_conditional_deinit" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/221X_virtual_contract_rejects_conditional_deinit",
        "violates its safety contract",
    );
}
