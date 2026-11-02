const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/04_expressions_and_type_inference" {
    const test_path = "tests/feature_tests/basics/04_expressions_and_type_inference";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 3);
}
