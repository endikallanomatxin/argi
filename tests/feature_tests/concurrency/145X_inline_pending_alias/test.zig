const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 145X_inline_pending_alias" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/145X_inline_pending_alias", "execution");
}
