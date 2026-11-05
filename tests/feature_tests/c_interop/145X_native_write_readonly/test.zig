const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 145X_native_write_readonly" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/145X_native_write_readonly", "writes requires a mutable reference input");
}
