const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/359X_return_local_error_trace" {
    try expectFrontendFailure("tests/feature_tests/ownership/359X_return_local_error_trace", "local storage generation");
}
