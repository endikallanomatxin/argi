const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/103X_partial_array_missing_element" {
    try buildExpectFail("tests/feature_tests/execution/103X_partial_array_missing_element", "deinitialized");
    try vmExpect("tests/feature_tests/execution/103X_partial_array_missing_element", 1, "deinitialized");
}
