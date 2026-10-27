const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/31X_virtual_contract_rejects_deinit" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/31X_virtual_contract_rejects_deinit",
        "violates its safety contract",
    );
}
