const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/64_generic_constraint_fallback" {
    const path = "tests/feature_tests/polymorphism/64_generic_constraint_fallback";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
