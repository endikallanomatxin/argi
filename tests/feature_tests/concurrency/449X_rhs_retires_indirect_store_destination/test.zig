const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "449X_rhs_retires_indirect_store_destination" {
    const path = "tests/feature_tests/concurrency/449X_rhs_retires_indirect_store_destination";
    try support.expectFrontendFailure(path, "reference depends on a root that has ended");
}
