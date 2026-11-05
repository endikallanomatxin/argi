const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 155X_native_bound_stale_wrapper" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/155X_native_bound_stale_wrapper", "reference depends on a root that has ended");
}
