const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/335X_ordered_requires_total" {
    try expectFrontendFailure("tests/feature_tests/contracts/335X_ordered_requires_total", "does not satisfy contract constraint 'TotalOrder'");
}
