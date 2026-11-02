const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/03_generic_functions" {
    const test_path = "tests/feature_tests/polymorphism/03_generic_functions";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}
