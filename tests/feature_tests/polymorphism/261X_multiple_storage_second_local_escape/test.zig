const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/261X_multiple_storage_second_local_escape" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/261X_multiple_storage_second_local_escape", "function output cannot depend on a local storage generation", "failed without a diagnostic");
}
