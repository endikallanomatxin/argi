const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/177X_virtual_relocates_alias" {
    try buildExpectFail("tests/feature_tests/polymorphism/177X_virtual_relocates_alias", "alias the same storage");
}
