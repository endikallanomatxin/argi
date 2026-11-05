const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 153X_native_erased_write_bound" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/153X_native_erased_write_bound", "native write bounds require reference-free storage");
}
