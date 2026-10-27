const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/190X_virtual_transfer_reconstructed_local" {
    try buildExpectFail("tests/feature_tests/polymorphism/190X_virtual_transfer_reconstructed_local", "cannot prove transfers");
}
