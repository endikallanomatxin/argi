const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/57X_output_default_keeps_old_generation" {
    try buildExpectFail("tests/feature_tests/execution/57X_output_default_keeps_old_generation", "reference depends on a root that has ended");
}
