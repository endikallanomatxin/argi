const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/52X_virtual_receiver_identity_same_type_argument" {
    try buildExpectFail("tests/feature_tests/polymorphism/52X_virtual_receiver_identity_same_type_argument", "root that has ended");
}
