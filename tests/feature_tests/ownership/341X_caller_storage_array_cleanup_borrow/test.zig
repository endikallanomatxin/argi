const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/341X_caller_storage_array_cleanup_borrow" {
    try expectFrontendFailure("tests/feature_tests/ownership/341X_caller_storage_array_cleanup_borrow", "local storage generation");
}
