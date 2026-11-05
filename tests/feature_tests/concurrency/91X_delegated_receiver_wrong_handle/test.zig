const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 91X_delegated_receiver_wrong_handle" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/91X_delegated_receiver_wrong_handle", "memory access exceeds the declared reads/writes bounds");
}
