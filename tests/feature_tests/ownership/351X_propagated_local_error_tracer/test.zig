const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/351X_propagated_local_error_tracer" {
    try expectFrontendFailure("tests/feature_tests/ownership/351X_propagated_local_error_tracer", "local storage generation");
}
