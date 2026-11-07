const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/415X_native_acquisition_from_bits" {
    try support.expectFrontendFailure("tests/feature_tests/types/415X_native_acquisition_from_bits", "requires an authenticated storage acquisition permission");
}
