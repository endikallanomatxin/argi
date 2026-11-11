const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "217X_whole_record_alias_before_lending" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/217X_whole_record_alias_before_lending", "pending execution");
}
