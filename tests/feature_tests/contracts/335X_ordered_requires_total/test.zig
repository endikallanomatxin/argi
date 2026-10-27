const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/335X_ordered_requires_total" {
    try buildExpectFail("tests/feature_tests/contracts/335X_ordered_requires_total", "does not satisfy contract constraint 'TotalOrder'");
}
