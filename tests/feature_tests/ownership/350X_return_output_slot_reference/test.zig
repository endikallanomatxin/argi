const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/350X_return_output_slot_reference" {
    try expectFrontendFailure("tests/feature_tests/ownership/350X_return_output_slot_reference", "local storage generation");
}
