const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/226X_virtual_contract_rejects_conditional_opaque_drop" {
    try buildExpectFail(
        "tests/feature_tests/ownership/226X_virtual_contract_rejects_conditional_opaque_drop",
        "violates its safety contract",
    );
}
