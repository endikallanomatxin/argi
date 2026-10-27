const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/248X_opaque_storage_conditional" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/248X_opaque_storage_conditional", "conditional opaque storage clauses require correlated hidden storage post-states", "failed without a diagnostic");
}
