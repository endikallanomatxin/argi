const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/383X_acquired_storage_foreign_result" {
    try support.expectFrontendFailure("tests/feature_tests/types/383X_acquired_storage_foreign_result", "unsupported C ABI type");
}
