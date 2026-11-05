const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 117X_generic_transfer_keeps_virtual_conflict" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/117X_generic_transfer_keeps_virtual_conflict", "pending execution");
}
