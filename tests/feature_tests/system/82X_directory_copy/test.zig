const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/82X_directory_copy" {
    try buildExpectFail("tests/feature_tests/system/82X_directory_copy", "cannot be copied implicitly");
}
