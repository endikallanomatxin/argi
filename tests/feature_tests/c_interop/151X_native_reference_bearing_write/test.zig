const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 151X_native_reference_bearing_write" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/151X_native_reference_bearing_write", "native write bounds require reference-free storage");
}
