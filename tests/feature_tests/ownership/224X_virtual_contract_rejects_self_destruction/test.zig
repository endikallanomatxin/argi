const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/224X_virtual_contract_rejects_self_destruction" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/224X_virtual_contract_rejects_self_destruction",
        "violates its safety contract",
    );
}
