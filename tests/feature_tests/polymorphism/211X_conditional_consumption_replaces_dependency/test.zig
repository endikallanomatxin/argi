const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/211X_conditional_consumption_replaces_dependency" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/211X_conditional_consumption_replaces_dependency", "maybe_initialized");
}
