const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/67X_local_binding_summary_dependency" {
    try expectFrontendFailure("tests/feature_tests/ownership/67X_local_binding_summary_dependency", "local storage generation");
}
