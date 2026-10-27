const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/233_init_argument_specialization" {
    const path = "tests/feature_tests/contracts/233_init_argument_specialization";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
