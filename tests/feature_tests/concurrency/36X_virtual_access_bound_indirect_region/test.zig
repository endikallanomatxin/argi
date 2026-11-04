const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 36X_virtual_access_bound_indirect_region" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/36X_virtual_access_bound_indirect_region", "memory access exceeds the declared reads/writes bounds");
}
