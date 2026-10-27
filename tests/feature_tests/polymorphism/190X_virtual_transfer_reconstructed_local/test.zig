const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/190X_virtual_transfer_reconstructed_local" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/190X_virtual_transfer_reconstructed_local", "cannot prove transfers");
}
