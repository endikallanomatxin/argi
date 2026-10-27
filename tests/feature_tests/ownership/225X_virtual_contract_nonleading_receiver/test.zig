const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/225X_virtual_contract_nonleading_receiver" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/225X_virtual_contract_nonleading_receiver",
        "violates its safety contract",
    );
}
