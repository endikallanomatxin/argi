const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/52X_dynamic_array_vacant_storage_reference" {
    try buildExpectFail(
        "tests/feature_tests/collections/52X_dynamic_array_vacant_storage_reference",
        "no function named 'trusted_dynamic_array_storage_pointer' exists",
    );
}
