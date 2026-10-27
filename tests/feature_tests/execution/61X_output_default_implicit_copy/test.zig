const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/61X_output_default_implicit_copy" {
    try buildExpectFail("tests/feature_tests/execution/61X_output_default_implicit_copy", "cannot be copied implicitly");
}
