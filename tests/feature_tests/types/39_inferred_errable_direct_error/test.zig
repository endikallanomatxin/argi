const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/39_inferred_errable_direct_error" {
    const test_path = "tests/feature_tests/types/39_inferred_errable_direct_error";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}
