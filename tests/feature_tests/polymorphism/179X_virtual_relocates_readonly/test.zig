const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/179X_virtual_relocates_readonly" {
    try buildExpectFail("tests/feature_tests/polymorphism/179X_virtual_relocates_readonly", "relocates requires mutable reference");
}
