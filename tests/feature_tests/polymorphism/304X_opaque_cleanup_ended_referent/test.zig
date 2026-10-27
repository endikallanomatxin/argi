const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/304X_opaque_cleanup_ended_referent" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/304X_opaque_cleanup_ended_referent", "opaque contents depend on a root that has ended", "failed without a diagnostic");
}
