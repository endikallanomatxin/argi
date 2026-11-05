const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 148X_native_bound_unknown_field" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/148X_native_bound_unknown_field", "access bound selects an unknown field");
}
