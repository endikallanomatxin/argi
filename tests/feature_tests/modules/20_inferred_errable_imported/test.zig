const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/20_inferred_errable_imported" {
    const test_path = "tests/feature_tests/modules/20_inferred_errable_imported";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 43);
}
