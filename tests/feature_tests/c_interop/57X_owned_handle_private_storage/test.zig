const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/57X_owned_handle_private_storage" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/57X_owned_handle_private_storage", "field '_handle' is private to its module", "failed without a diagnostic");
}
