const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 44X_indirect_access_readonly_field" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/44X_indirect_access_readonly_field", "writes requires a mutable reference at the selected access path");
}
