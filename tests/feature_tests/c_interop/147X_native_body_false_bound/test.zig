const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 147X_native_body_false_bound" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/147X_native_body_false_bound", "native function body violates its declared access bounds");
}
