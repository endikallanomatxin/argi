const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/328_generic_else_if" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/328_generic_else_if");
    try runExpect("tests/feature_tests/polymorphism/328_generic_else_if", 0);
}
