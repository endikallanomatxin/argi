const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/26X_print_without_system" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/io/26X_print_without_system", "no generic function named 'print' accepts arguments", "panic");
}
