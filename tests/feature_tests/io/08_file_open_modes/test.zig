const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/08_file_open_modes" {
    const test_path = "tests/feature_tests/io/08_file_open_modes";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
