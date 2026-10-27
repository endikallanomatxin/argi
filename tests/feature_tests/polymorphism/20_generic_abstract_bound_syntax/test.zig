const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/20_generic_abstract_bound_syntax" {
    const test_path = "tests/feature_tests/polymorphism/20_generic_abstract_bound_syntax";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}
