const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/35X_nested_pipe_requires_outer_placeholder" {
    try buildExpectFail("tests/feature_tests/functions/35X_nested_pipe_requires_outer_placeholder", "pipe right-hand side must use at least one argument placeholder");
}
