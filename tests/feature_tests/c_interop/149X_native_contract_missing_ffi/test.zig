const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 149X_native_contract_missing_ffi" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/149X_native_contract_missing_ffi", "missing required argument '.ffi'");
}
