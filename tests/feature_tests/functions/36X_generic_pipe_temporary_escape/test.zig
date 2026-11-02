const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/36X_generic_pipe_temporary_escape" {
    try expectFrontendFailure("tests/feature_tests/functions/36X_generic_pipe_temporary_escape", "local storage generation");
}
