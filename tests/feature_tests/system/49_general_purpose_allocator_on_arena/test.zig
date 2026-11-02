const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/49_general_purpose_allocator_on_arena" {
    const test_path = "tests/feature_tests/system/49_general_purpose_allocator_on_arena";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
