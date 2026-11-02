const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/223X_conditional_relocates_shared_source" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/223X_conditional_relocates_shared_source", "alias the same storage");
}
