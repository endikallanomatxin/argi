const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/37X_pipe_temporary_consumed_twice" {
    try buildExpectFail(
        "tests/feature_tests/functions/37X_pipe_temporary_consumed_twice",
        "was moved and cannot be used again",
    );
}
