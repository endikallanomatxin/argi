const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "212X_helper_alias_reference_expires_in_caller" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/212X_helper_alias_reference_expires_in_caller", "root that has ended");
}
