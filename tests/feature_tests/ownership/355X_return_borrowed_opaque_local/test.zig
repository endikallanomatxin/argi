const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/355X_return_borrowed_opaque_local" {
    try expectFrontendFailure("tests/feature_tests/ownership/355X_return_borrowed_opaque_local", "local storage generation");
}
