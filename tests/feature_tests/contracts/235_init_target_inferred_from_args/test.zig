const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/235_init_target_inferred_from_args" {
    const path = "tests/feature_tests/contracts/235_init_target_inferred_from_args";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
