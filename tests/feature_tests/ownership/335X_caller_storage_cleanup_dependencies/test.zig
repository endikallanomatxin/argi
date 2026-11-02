const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/335X_caller_storage_cleanup_dependencies" {
    try expectFrontendFailure("tests/feature_tests/ownership/335X_caller_storage_cleanup_dependencies", "local storage generation");
}
