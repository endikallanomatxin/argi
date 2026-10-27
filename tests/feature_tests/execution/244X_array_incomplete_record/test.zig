const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/244X_array_incomplete_record" {
    try buildExpectFail("tests/feature_tests/execution/244X_array_incomplete_record", "record initializer is missing required field 'right'");
    try vmExpect("tests/feature_tests/execution/244X_array_incomplete_record", 1, "record initializer is missing required field 'right'");
}
