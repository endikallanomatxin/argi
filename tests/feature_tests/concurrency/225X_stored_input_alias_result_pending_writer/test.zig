const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "225X_stored_input_alias_result_pending_writer" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/225X_stored_input_alias_result_pending_writer", "pending execution");
}
