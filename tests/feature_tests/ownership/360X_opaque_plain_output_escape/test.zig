const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/360X_opaque_plain_output_escape" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/ownership/360X_opaque_plain_output_escape", "function output cannot depend on a local storage generation", "failed without a diagnostic");
}
