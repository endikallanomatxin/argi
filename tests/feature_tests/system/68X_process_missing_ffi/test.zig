const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/68X_process_missing_ffi" {
    try buildExpectFail("tests/feature_tests/system/68X_process_missing_ffi", "Init argument '.ffi' requires a reachable value or an explicit argument");
}
