const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/179X_virtual_relocates_readonly" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/179X_virtual_relocates_readonly", "relocates requires mutable reference");
}
