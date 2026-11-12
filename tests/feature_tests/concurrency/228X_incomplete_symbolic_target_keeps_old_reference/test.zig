const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "228X_incomplete_symbolic_target_keeps_old_reference" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/228X_incomplete_symbolic_target_keeps_old_reference", "root that has ended");
}
