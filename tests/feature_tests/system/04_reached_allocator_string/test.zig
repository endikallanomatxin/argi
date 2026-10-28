const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/04_reached_allocator_string" {
    const test_path = "tests/feature_tests/system/04_reached_allocator_string";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 11);
}
