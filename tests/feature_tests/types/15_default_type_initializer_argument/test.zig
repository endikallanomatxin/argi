const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/15_default_type_initializer_argument" {
    const test_path = "tests/feature_tests/types/15_default_type_initializer_argument";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 7);
}
