const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/328X_caller_storage_virtual" {
    try expectFrontendFailure("tests/feature_tests/ownership/328X_caller_storage_virtual", "local storage generation");
}
