const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/226X_virtual_relocates_inherited_consumes" {
    try buildExpectFail("tests/feature_tests/polymorphism/226X_virtual_relocates_inherited_consumes", "relocates and consumes cannot target the same input");
}
