const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/330X_ordered_result_signature" {
    try buildExpectFail("tests/feature_tests/contracts/330X_ordered_result_signature", "operation returns an incompatible associated result");
}
