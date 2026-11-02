const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/354X_return_opaque_local_borrow" {
    try expectFrontendFailure("tests/feature_tests/ownership/354X_return_opaque_local_borrow", "local storage generation");
}
