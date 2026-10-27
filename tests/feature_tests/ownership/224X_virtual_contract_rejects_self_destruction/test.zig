const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/224X_virtual_contract_rejects_self_destruction" {
    try buildExpectFail(
        "tests/feature_tests/ownership/224X_virtual_contract_rejects_self_destruction",
        "violates its safety contract",
    );
}
