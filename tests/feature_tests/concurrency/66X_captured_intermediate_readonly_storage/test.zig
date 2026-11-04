const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 66X_captured_intermediate_readonly_storage" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/66X_captured_intermediate_readonly_storage", "writes requires mutable storage or a mutable reference");
}
