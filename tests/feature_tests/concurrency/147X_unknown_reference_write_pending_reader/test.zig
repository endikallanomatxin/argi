const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "147X_unknown_reference_write_pending_reader" {
    const path = "tests/feature_tests/concurrency/147X_unknown_reference_write_pending_reader";
    try support.expectFrontendFailure(path, "reference access has unknown memory effects");
}
