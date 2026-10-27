const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/342X_caller_storage_array_cleanup" {
    try expectFrontendFailure("tests/feature_tests/ownership/342X_caller_storage_array_cleanup", "local storage generation");
}
