const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/271_constructor_choice_context" {
    const path = "tests/feature_tests/types/271_constructor_choice_context";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
