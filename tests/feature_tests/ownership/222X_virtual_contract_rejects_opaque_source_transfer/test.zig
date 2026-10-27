const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/222X_virtual_contract_rejects_opaque_source_transfer" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/222X_virtual_contract_rejects_opaque_source_transfer",
        "violates its safety contract",
    );
}
