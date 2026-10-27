const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/176X_virtual_relocates_use_after" {
    try buildExpectFail("tests/feature_tests/polymorphism/176X_virtual_relocates_use_after", "moved");
}
