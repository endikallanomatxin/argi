const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/40_inferred_errable_explicit_output" {
    const test_path = "tests/feature_tests/types/40_inferred_errable_explicit_output";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 40);
}
