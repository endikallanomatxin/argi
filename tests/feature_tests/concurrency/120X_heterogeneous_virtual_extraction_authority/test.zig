const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 120X_heterogeneous_virtual_extraction_authority" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/120X_heterogeneous_virtual_extraction_authority", "cannot establish captured access region identity");
}
