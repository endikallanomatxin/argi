const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/189X_virtual_referent_wrong_local" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/189X_virtual_referent_wrong_local", "cannot prove refers_to");
}
