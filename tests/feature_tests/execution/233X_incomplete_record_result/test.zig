const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/233X_incomplete_record_result" {
    try buildExpectFail("tests/feature_tests/execution/233X_incomplete_record_result", "record initializer is missing required field 'right'");
    try vmExpect("tests/feature_tests/execution/233X_incomplete_record_result", 1, "record initializer is missing required field 'right'");
}
