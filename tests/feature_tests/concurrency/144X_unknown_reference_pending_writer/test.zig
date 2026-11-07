const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "144X_unknown_reference_pending_writer" {
    const path = "tests/feature_tests/concurrency/144X_unknown_reference_pending_writer";
    try support.expectFrontendFailure(path, "reference access has unknown memory effects");
}
