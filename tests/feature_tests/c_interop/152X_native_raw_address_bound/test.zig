const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 152X_native_raw_address_bound" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/152X_native_raw_address_bound", "reads and writes require a reference input");
}
