const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/04X_missing_operation" {
    try buildExpectFail("tests/feature_tests/contracts/04X_missing_operation", "missing implementation operation");
}
