const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/83X_directory_after_cleanup" {
    try buildExpectFail("tests/feature_tests/system/83X_directory_after_cleanup", "root that has ended");
}
