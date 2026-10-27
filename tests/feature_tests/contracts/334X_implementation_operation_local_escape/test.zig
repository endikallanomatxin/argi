const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/334X_implementation_operation_local_escape" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/334X_implementation_operation_local_escape", "local storage", "panic");
}
