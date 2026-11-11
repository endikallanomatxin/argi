const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "215X_projected_helper_alias_before_lending" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/215X_projected_helper_alias_before_lending", "pending execution");
}
