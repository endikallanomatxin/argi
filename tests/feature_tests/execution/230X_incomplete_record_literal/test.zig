const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/230X_incomplete_record_literal" {
    try buildExpectFail("tests/feature_tests/execution/230X_incomplete_record_literal", "record initializer is missing required field 'right'");
    try vmExpect("tests/feature_tests/execution/230X_incomplete_record_literal", 1, "record initializer is missing required field 'right'");
}
