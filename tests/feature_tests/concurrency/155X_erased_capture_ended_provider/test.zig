const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 155X_erased_capture_ended_provider" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/155X_erased_capture_ended_provider", "dependency");
}
