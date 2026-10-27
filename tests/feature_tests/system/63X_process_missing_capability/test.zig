const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/63X_process_missing_capability" {
    try buildExpectFail("tests/feature_tests/system/63X_process_missing_capability", ".self uses reach [proc_man] expected as '&ProcessManager'");
}
