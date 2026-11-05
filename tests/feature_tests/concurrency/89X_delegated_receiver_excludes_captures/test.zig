const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 89X_delegated_receiver_excludes_captures" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/89X_delegated_receiver_excludes_captures", "memory access exceeds the declared reads/writes bounds");
}
