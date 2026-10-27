const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/08X_ambiguous_operation" {
    try buildExpectFail("tests/feature_tests/contracts/08X_ambiguous_operation", "ambiguous conformances for the same participant tuple");
}
