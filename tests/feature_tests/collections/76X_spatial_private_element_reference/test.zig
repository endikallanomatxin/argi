const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/76X_spatial_private_element_reference" {
    try expectFrontendFailure("tests/feature_tests/collections/76X_spatial_private_element_reference", "no function named '_trusted_dynamic_array_element_reference' exists");
}
