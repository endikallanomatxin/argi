const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "411X_opaque_retains_freed_heap_borrow" {
    const path = "tests/feature_tests/types/411X_opaque_retains_freed_heap_borrow";
    try support.expectFrontendFailure(path, "ended");
}
