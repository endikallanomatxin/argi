const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/60X_concrete_output_default_consumption" {
    try buildExpectFail("tests/feature_tests/execution/60X_concrete_output_default_consumption", "consumption requires an initialized owner");
}
