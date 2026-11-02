const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/302X_concrete_read_ended_opaque_contents" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/302X_concrete_read_ended_opaque_contents", "opaque contents depend on a root that has ended", "failed without a diagnostic");
}
