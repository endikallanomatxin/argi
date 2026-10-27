const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/297X_virtual_receiver_ended_opaque_contents" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/297X_virtual_receiver_ended_opaque_contents", "receiver contents depend on a root that has ended", "failed without a diagnostic");
}
