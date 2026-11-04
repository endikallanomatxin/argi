const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 13X_loop_backing" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/13X_loop_backing", "pending execution");
}
