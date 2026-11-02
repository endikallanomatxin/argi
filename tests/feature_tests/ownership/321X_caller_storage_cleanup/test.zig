const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/321X_caller_storage_cleanup" {
    try expectFrontendFailure("tests/feature_tests/ownership/321X_caller_storage_cleanup", "local storage generation");
}
