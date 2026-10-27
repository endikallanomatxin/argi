const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/51X_virtual_readonly_generic_conversion" {
    try buildExpectFail("tests/feature_tests/polymorphism/51X_virtual_readonly_generic_conversion", "a mutable participant receiver requires a mutable concrete reference");
}
