const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/22_file_system_mutations" {
    const test_path = "tests/feature_tests/system/22_file_system_mutations";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
