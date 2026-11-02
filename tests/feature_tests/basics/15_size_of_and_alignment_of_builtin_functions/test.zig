const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/15_size_of_and_alignment_of_builtin_functions" {
    const test_path = "tests/feature_tests/basics/15_size_of_and_alignment_of_builtin_functions";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
