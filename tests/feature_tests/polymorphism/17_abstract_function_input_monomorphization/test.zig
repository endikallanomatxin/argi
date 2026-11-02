const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/17_abstract_function_input_monomorphization" {
    const test_path = "tests/feature_tests/polymorphism/17_abstract_function_input_monomorphization";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 7);
}
