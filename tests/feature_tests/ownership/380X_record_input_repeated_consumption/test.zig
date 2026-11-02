const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/380X_record_input_repeated_consumption" {
    try expectFrontendFailure("tests/feature_tests/ownership/380X_record_input_repeated_consumption", "consumption requires an initialized owner");
}
