const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/341X_tag_choice_nominal_identity" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/341X_tag_choice_nominal_identity", "no conformance for the qualified operation's participants", "without a diagnostic");
}
