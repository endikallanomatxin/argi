const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/99X_dynamic_array_virtual_adapter_local_provider" {
    try support.expectFrontendFailure(
        "tests/feature_tests/system/99X_dynamic_array_virtual_adapter_local_provider",
        "local storage generation",
    );
}
