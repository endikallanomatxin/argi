const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/37X_system_local_resource_escape" {
    try expectFrontendFailure("tests/feature_tests/system/37X_system_local_resource_escape", "local storage generation");
}
