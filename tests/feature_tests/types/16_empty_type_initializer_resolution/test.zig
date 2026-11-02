const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/16_empty_type_initializer_resolution" {
    const test_path = "tests/feature_tests/types/16_empty_type_initializer_resolution";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
