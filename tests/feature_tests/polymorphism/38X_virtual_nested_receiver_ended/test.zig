const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/38X_virtual_nested_receiver_ended" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/38X_virtual_nested_receiver_ended",
        "reference depends on a root that has ended",
    );
}
