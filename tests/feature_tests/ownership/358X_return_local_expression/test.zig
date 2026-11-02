const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/358X_return_local_expression" {
    try expectFrontendFailure("tests/feature_tests/ownership/358X_return_local_expression", "local storage generation");
}
