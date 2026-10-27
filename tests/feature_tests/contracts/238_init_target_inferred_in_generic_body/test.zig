const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/238_init_target_inferred_in_generic_body" {
    const path = "tests/feature_tests/contracts/238_init_target_inferred_in_generic_body";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
