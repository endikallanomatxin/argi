const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/228X_virtual_relocates_occupied" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/228X_virtual_relocates_occupied", "relocate destination is initialized");
}
