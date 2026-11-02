const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/223X_virtual_contract_rejects_ambiguous_opaque_storage" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/223X_virtual_contract_rejects_ambiguous_opaque_storage",
        "violates its safety contract",
    );
}
