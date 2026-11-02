const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/234X_virtual_relocates_alternative_destinations" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/234X_virtual_relocates_alternative_destinations", "alternative relocates clauses sharing an input must describe the same source and destination");
}
