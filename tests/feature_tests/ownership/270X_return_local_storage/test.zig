const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/270X_return_local_storage" {
    try expectFrontendFailure("tests/feature_tests/ownership/270X_return_local_storage", "local storage generation");
}
