const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 90X_handle_bound_excludes_erased_receiver" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/90X_handle_bound_excludes_erased_receiver", "memory access exceeds the declared reads/writes bounds");
}
