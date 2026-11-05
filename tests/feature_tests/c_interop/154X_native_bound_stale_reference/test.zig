const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 154X_native_bound_stale_reference" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/154X_native_bound_stale_reference", "reference depends on a root that has ended");
}
