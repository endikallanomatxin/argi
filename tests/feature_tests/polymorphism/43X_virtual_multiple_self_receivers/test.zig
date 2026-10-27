const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/43X_virtual_multiple_self_receivers" {
    try buildExpectFail("tests/feature_tests/polymorphism/43X_virtual_multiple_self_receivers", "exactly one borrowed participant receiver");
}
