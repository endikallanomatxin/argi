const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/47X_virtual_missing_receiver" {
    try buildExpectFail("tests/feature_tests/polymorphism/47X_virtual_missing_receiver", "exactly one borrowed participant receiver");
}
