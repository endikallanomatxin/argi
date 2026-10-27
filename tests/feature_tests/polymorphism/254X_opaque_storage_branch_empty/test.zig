const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/254X_opaque_storage_branch_empty" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/254X_opaque_storage_branch_empty", "cannot prove empties", "failed without a diagnostic");
}
