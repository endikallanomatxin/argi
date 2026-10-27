const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/243_init_nested_reference_effects" {
    const path = "tests/feature_tests/contracts/243_init_nested_reference_effects";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
