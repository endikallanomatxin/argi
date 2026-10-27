const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/220X_virtual_contract_rejects_hidden_dependency" {
    try buildExpectFail(
        "tests/feature_tests/ownership/220X_virtual_contract_rejects_hidden_dependency",
        "violates its safety contract",
    );
}
