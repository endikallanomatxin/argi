const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/40X_virtual_nested_aggregate_borrow" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/40X_virtual_nested_aggregate_borrow",
        "reference depends on a root that has ended",
    );
}
