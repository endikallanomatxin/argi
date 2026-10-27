const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/52X_virtual_receiver_identity_same_type_argument" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/52X_virtual_receiver_identity_same_type_argument", "root that has ended");
}
