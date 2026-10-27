const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/02X_multiple_dispatch_ambiguous" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/02X_multiple_dispatch_ambiguous", "ambiguous maximal patterns", "failed without a diagnostic");
}
