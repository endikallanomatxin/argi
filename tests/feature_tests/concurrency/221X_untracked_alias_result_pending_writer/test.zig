const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "221X_untracked_alias_result_pending_writer" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/221X_untracked_alias_result_pending_writer", "pending execution");
}
