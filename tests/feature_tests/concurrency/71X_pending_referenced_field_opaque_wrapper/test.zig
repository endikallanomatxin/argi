const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 71X_pending_referenced_field_opaque_wrapper" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/71X_pending_referenced_field_opaque_wrapper", "cannot hide a pending execution in opaque storage without its completion protocol");
}
