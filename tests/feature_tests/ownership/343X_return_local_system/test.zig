const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/343X_return_local_system" {
    try expectFrontendFailure("tests/feature_tests/ownership/343X_return_local_system", "local storage generation");
}
