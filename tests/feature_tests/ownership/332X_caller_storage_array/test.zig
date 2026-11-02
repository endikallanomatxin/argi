const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/332X_caller_storage_array" {
    try expectFrontendFailure("tests/feature_tests/ownership/332X_caller_storage_array", "local storage generation");
}
