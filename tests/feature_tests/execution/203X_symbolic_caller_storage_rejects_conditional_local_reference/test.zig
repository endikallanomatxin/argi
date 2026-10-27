const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/203X_symbolic_caller_storage_rejects_conditional_local_reference" {
    try buildExpectFail("tests/feature_tests/execution/203X_symbolic_caller_storage_rejects_conditional_local_reference", "caller storage cannot depend on a local storage generation");
    try vmExpect("tests/feature_tests/execution/203X_symbolic_caller_storage_rejects_conditional_local_reference", 1, "caller storage cannot depend on a local storage generation");
}
