const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 150X_native_empty_contract_is_unknown" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/150X_native_empty_contract_is_unknown", "cannot prove access bounds: implementation has unknown or global memory effects");
}
