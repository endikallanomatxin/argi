const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 84X_primitive_move_exceeds_access_bound" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/84X_primitive_move_exceeds_access_bound", "memory access exceeds the declared reads/writes bounds");
}
