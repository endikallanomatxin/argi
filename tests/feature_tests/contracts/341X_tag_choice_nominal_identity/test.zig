const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/341X_tag_choice_nominal_identity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/341X_tag_choice_nominal_identity", "no conformance for the qualified operation's participants", "without a diagnostic");
}
