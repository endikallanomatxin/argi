const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/242_init_explicit_native_capabilities" {
    const path = "tests/feature_tests/contracts/242_init_explicit_native_capabilities";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
