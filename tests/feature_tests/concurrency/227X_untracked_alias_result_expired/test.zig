const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "227X_untracked_alias_result_expired" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/227X_untracked_alias_result_expired", "root that has ended");
}
