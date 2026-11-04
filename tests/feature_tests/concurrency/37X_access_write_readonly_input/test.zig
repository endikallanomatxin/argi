const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 37X_access_write_readonly_input" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/37X_access_write_readonly_input", "writes requires a mutable reference input");
}
