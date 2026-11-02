const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/40X_virtual_nested_aggregate_borrow" {
    try expectFrontendFailure(
        "tests/feature_tests/polymorphism/40X_virtual_nested_aggregate_borrow",
        "reference depends on a root that has ended",
    );
}
