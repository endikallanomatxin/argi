const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 156X_native_stored_reference_bound" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/156X_native_stored_reference_bound", "native access bounds cannot follow stored references");
}
