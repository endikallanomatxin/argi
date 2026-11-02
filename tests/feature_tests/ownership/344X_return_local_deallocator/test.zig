const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/344X_return_local_deallocator" {
    try expectFrontendFailure("tests/feature_tests/ownership/344X_return_local_deallocator", "local storage generation");
}
