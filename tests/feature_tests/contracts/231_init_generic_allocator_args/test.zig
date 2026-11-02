const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/231_init_generic_allocator_args" {
    const path = "tests/feature_tests/contracts/231_init_generic_allocator_args";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
