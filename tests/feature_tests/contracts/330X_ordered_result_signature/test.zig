const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/330X_ordered_result_signature" {
    try expectFrontendFailure("tests/feature_tests/contracts/330X_ordered_result_signature", "operation returns an incompatible associated result");
}
