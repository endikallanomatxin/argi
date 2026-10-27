const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/49X_array_view_unproven_length" {
    try expectFrontendFailure(
        "tests/feature_tests/collections/49X_array_view_unproven_length",
        "no generic function named 'single_mutable_array_view' accepts arguments",
    );
}
