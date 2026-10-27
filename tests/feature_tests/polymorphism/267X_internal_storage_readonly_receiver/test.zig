const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/267X_internal_storage_readonly_receiver" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/267X_internal_storage_readonly_receiver", "retains and empties require mutable storage references", "failed without a diagnostic");
}
