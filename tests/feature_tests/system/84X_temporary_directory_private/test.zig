const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/84X_temporary_directory_private" {
    try buildExpectFail("tests/feature_tests/system/84X_temporary_directory_private", "field '_handle' is private");
}
