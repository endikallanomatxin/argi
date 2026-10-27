const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/174X_virtual_relocates_missing" {
    try buildExpectFail("tests/feature_tests/polymorphism/174X_virtual_relocates_missing", "cannot prove relocates");
}
