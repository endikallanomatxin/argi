const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/382X_acquired_storage_zeroed" {
    try support.expectFrontendFailure("tests/feature_tests/types/382X_acquired_storage_zeroed", "resource-bearing types cannot be zero-initialized");
}
