const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/355X_generic_choice_field_invalid" {
    try support.expectFrontendFailureWithoutParseNoise(
        "tests/feature_tests/contracts/355X_generic_choice_field_invalid",
        "no generic function named 'set_invalid' accepts arguments",
    );
}
