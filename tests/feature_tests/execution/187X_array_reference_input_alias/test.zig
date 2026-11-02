const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/187X_array_reference_input_alias" {
    try buildExpectFail("tests/feature_tests/execution/187X_array_reference_input_alias", "aliased participant has consumed its value");
    try vmExpect("tests/feature_tests/execution/187X_array_reference_input_alias", 1, "aliased participant has consumed its value");
}
