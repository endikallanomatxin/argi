const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/324X_caller_storage_loop" {
    try expectFrontendFailure("tests/feature_tests/ownership/324X_caller_storage_loop", "local storage generation");
}
