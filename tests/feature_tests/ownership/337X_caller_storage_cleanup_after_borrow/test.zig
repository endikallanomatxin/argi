const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/337X_caller_storage_cleanup_after_borrow" {
    try expectFrontendFailure("tests/feature_tests/ownership/337X_caller_storage_cleanup_after_borrow", "local storage generation");
}
