const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/264X_internal_storage_retained_local_escape" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/264X_internal_storage_retained_local_escape", "function output cannot depend on a local storage generation", "failed without a diagnostic");
}
