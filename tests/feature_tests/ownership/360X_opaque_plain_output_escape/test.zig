const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/360X_opaque_plain_output_escape" {
    try buildExpectFailWithoutNoise("tests/feature_tests/ownership/360X_opaque_plain_output_escape", "function output cannot depend on a local storage generation", "failed without a diagnostic");
}
