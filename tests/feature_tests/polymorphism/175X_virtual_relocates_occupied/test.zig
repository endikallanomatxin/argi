const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/175X_virtual_relocates_occupied" {
    try buildExpectFail("tests/feature_tests/polymorphism/175X_virtual_relocates_occupied", "relocate destination is initialized");
}
