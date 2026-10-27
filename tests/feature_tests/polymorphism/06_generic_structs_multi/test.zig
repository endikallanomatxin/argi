const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/06_generic_structs_multi" {
    const test_path = "tests/feature_tests/polymorphism/06_generic_structs_multi";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 20);
}
