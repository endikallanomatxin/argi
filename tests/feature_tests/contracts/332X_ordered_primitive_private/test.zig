const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/332X_ordered_primitive_private" {
    try expectFrontendFailure("tests/feature_tests/contracts/332X_ordered_primitive_private", "no generic function");
}
