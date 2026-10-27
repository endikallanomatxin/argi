const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/247X_opaque_storage_missing_empty" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/247X_opaque_storage_missing_empty", "cannot prove empties", "failed without a diagnostic");
}
