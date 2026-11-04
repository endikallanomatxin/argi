const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 09X_replace_owner" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/09X_replace_owner", "pending execution");
}
