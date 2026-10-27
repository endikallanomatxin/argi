const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/17_multi_file_module_forward_calls" {
    const test_path = "tests/feature_tests/modules/17_multi_file_module_forward_calls";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
