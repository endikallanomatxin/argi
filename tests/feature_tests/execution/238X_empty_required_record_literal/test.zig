const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/238X_empty_required_record_literal" {
    try buildExpectFail("tests/feature_tests/execution/238X_empty_required_record_literal", "record initializer is missing required field 'answer'");
    try vmExpect("tests/feature_tests/execution/238X_empty_required_record_literal", 1, "record initializer is missing required field 'answer'");
}
