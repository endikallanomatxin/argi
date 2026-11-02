const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/69X_system_storage_escape" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/system/69X_system_storage_escape", "function output cannot depend on a local storage generation", "failed without a diagnostic");
}
