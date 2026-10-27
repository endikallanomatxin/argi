const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/323X_caller_storage_branches" {
    try expectFrontendFailure("tests/feature_tests/ownership/323X_caller_storage_branches", "local storage generation");
}
