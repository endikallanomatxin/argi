const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/258X_opaque_storage_forwarded_local_escape" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/258X_opaque_storage_forwarded_local_escape", "function output cannot depend on a local storage generation", "failed without a diagnostic");
}
