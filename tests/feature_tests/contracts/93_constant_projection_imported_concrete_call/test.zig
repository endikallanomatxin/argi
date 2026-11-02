const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/93_constant_projection_imported_concrete_call" {
    const path = "tests/feature_tests/contracts/93_constant_projection_imported_concrete_call";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
