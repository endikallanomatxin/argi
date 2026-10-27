const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/52X_dynamic_array_vacant_storage_reference" {
    try expectFrontendFailure(
        "tests/feature_tests/collections/52X_dynamic_array_vacant_storage_reference",
        "no function named 'trusted_dynamic_array_storage_pointer' exists",
    );
}
