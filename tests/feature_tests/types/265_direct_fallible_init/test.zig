const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/265_direct_fallible_init" {
    const test_path = "tests/feature_tests/types/265_direct_fallible_init";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
