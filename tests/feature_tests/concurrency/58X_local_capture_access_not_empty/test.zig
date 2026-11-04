const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 58X_local_capture_access_not_empty" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/58X_local_capture_access_not_empty", "violates its safety contract");
}
