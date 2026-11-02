const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/151X_scoped_virtual_receiver_dependencies" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/151X_scoped_virtual_receiver_dependencies", "a storage transition is not permitted by this preservation contract", "_implement$");
}
