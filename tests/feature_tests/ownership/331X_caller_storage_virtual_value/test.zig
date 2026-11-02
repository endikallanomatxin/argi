const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/331X_caller_storage_virtual_value" {
    try expectFrontendFailure("tests/feature_tests/ownership/331X_caller_storage_virtual_value", "local storage generation");
}
