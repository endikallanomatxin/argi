const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "213X_replaced_stored_alias_before_lending" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/213X_replaced_stored_alias_before_lending", "pending execution");
}
