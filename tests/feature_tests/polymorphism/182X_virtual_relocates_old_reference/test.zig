const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/182X_virtual_relocates_old_reference" {
    try buildExpectFail("tests/feature_tests/polymorphism/182X_virtual_relocates_old_reference", "reference depends on a root that has ended");
}
