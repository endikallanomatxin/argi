const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 123X_unknown_virtual_pending_writer" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/123X_unknown_virtual_pending_writer", "call has unknown memory effects while a pending execution retains borrowed storage");
}
