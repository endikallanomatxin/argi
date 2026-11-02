const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/154X_virtual_contract_alias_obligation" {
    try expectFrontendFailure("tests/feature_tests/execution/154X_virtual_contract_alias_obligation", "a caller-side storage alias obligation is not represented by this contract");
}
