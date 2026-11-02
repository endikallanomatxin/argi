const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/54X_owned_handle_copy" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/54X_owned_handle_copy", "cannot be copied implicitly", "failed without a diagnostic");
}
