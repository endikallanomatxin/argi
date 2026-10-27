const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/37X_pipe_temporary_consumed_twice" {
    try expectFrontendFailure(
        "tests/feature_tests/functions/37X_pipe_temporary_consumed_twice",
        "was moved and cannot be used again",
    );
}
