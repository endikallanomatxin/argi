const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/380X_record_input_repeated_consumption" {
    try buildExpectFail("tests/feature_tests/ownership/380X_record_input_repeated_consumption", "consumption requires an initialized owner");
}
