const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/229X_virtual_relocates_expired_reference" {
    try buildExpectFail("tests/feature_tests/polymorphism/229X_virtual_relocates_expired_reference", "reference depends on a root that has ended");
}
