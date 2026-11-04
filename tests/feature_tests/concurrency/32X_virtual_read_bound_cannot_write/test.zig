const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 32X_virtual_read_bound_cannot_write" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/32X_virtual_read_bound_cannot_write", "memory access exceeds the declared reads/writes bounds");
}
