const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/102X_acquired_storage_private_subaddress" {
    try expectFrontendFailure("tests/feature_tests/types/102X_acquired_storage_private_subaddress", "no function named '_trusted_acquisition_subaddress' exists");
}
