const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/240_init_once_operation_alias" {
    const path = "tests/feature_tests/contracts/240_init_once_operation_alias";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
