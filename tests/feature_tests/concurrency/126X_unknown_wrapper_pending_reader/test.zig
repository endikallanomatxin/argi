const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 126X_unknown_wrapper_pending_reader" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/126X_unknown_wrapper_pending_reader", "call has unknown memory effects while a pending execution retains borrowed storage");
}
