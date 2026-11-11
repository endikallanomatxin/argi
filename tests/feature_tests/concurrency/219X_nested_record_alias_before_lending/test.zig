const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "219X_nested_record_alias_before_lending" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/219X_nested_record_alias_before_lending", "pending execution");
}
