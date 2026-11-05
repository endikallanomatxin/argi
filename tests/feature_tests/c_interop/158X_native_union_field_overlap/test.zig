const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 158X_native_union_field_overlap" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/158X_native_union_field_overlap", "concurrent access conflicts with a pending execution");
}
