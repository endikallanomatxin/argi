const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/159X_deallocator_global_operation" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/159X_deallocator_global_operation", "no function named 'deallocate' exists", "panic");
}
