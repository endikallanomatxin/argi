const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/253X_opaque_storage_backing_reference" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/253X_opaque_storage_backing_reference", "undeclared output dependency", "failed without a diagnostic");
}
