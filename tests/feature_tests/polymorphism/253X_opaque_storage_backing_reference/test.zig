const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/253X_opaque_storage_backing_reference" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/253X_opaque_storage_backing_reference", "undeclared output dependency", "failed without a diagnostic");
}
