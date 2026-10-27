const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/191X_reference_self_initialization" {
    try buildExpectFail("tests/feature_tests/execution/191X_reference_self_initialization", "value was deinitialized");
    try vmExpect("tests/feature_tests/execution/191X_reference_self_initialization", 1, "value was deinitialized");
}
