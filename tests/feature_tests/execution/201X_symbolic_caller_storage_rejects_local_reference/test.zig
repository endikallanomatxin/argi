const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/201X_symbolic_caller_storage_rejects_local_reference" {
    try buildExpectFail("tests/feature_tests/execution/201X_symbolic_caller_storage_rejects_local_reference", "caller storage cannot depend on a local storage generation");
    try vmExpect("tests/feature_tests/execution/201X_symbolic_caller_storage_rejects_local_reference", 1, "caller storage cannot depend on a local storage generation");
}
