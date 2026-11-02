const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/227X_virtual_contract_rejects_opaque_drop" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/227X_virtual_contract_rejects_opaque_drop",
        "violates its safety contract",
    );
}
