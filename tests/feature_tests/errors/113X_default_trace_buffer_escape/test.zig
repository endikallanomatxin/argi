const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "default tracer buffer cannot escape its caller storage" {
    try support.expectFrontendFailure("tests/feature_tests/errors/113X_default_trace_buffer_escape", "function output cannot depend on a local storage generation");
}
