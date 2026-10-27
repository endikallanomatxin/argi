const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/26_inferred_shorthand_omitted_reasons_transitive" {
    const test_path = "tests/feature_tests/modules/26_inferred_shorthand_omitted_reasons_transitive";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 46);
}
