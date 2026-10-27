const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/227_structural_args_allocator_inference" {
    const path = "tests/feature_tests/contracts/227_structural_args_allocator_inference";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
