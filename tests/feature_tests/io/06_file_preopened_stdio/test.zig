const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/06_file_preopened_stdio" {
    const test_path = "tests/feature_tests/io/06_file_preopened_stdio";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
