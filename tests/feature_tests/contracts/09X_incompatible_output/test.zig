const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/09X_incompatible_output" {
    try buildExpectFail("tests/feature_tests/contracts/09X_incompatible_output", "operation returns an incompatible associated result");
}
