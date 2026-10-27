const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/08_string_allocator_size" {
    const test_path = "tests/feature_tests/text/08_string_allocator_size";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
