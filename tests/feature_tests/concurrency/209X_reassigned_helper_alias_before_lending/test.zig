const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "209X_reassigned_helper_alias_before_lending" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/209X_reassigned_helper_alias_before_lending", "pending execution");
}
