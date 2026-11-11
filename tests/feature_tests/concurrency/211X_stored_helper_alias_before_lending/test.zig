const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "211X_stored_helper_alias_before_lending" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/211X_stored_helper_alias_before_lending", "pending execution");
}
