const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/225X_virtual_contract_nonleading_receiver" {
    try buildExpectFail(
        "tests/feature_tests/ownership/225X_virtual_contract_nonleading_receiver",
        "violates its safety contract",
    );
}
