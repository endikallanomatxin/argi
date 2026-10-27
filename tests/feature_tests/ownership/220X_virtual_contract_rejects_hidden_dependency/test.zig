const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/220X_virtual_contract_rejects_hidden_dependency" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/220X_virtual_contract_rejects_hidden_dependency",
        "violates its safety contract",
    );
}

test "tests/feature_tests/ownership/220X_virtual_contract_rejects_hidden_dependency wrapper parity" {
    try support.expectSafetyWrapperParity("tests/feature_tests/ownership/220X_virtual_contract_rejects_hidden_dependency", "violates its safety contract");
}
