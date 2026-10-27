const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/325X_caller_storage_recursive" {
    try expectFrontendFailure("tests/feature_tests/ownership/325X_caller_storage_recursive", "local storage generation");
}
