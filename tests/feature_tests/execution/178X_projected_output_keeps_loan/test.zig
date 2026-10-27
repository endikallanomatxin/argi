const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/178X_projected_output_keeps_loan" {
    try buildExpectFail("tests/feature_tests/execution/178X_projected_output_keeps_loan", "root that has ended");
}
