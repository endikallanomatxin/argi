const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "356X_concurrent_alias_ordinary_pending_loan" {
    const path = "tests/feature_tests/concurrency/356X_concurrent_alias_ordinary_pending_loan";
    try support.expectFrontendFailure(path, "pending execution");
}
