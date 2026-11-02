const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/67X_error_tracer_escape" {
    try expectFrontendFailure("tests/feature_tests/types/67X_error_tracer_escape", "local storage generation");
}
