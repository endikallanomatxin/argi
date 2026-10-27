const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/10X_static_safety_dependency" {
    try expectFrontendFailure("tests/feature_tests/contracts/10X_static_safety_dependency", "undeclared output dependency");
}
