const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/333X_caller_storage_large_return" {
    try expectFrontendFailure("tests/feature_tests/ownership/333X_caller_storage_large_return", "local storage generation");
}
