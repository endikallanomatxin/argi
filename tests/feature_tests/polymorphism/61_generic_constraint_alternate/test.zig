const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/61_generic_constraint_alternate" {
    const path = "tests/feature_tests/polymorphism/61_generic_constraint_alternate";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
