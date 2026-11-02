const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/26_arithmetic_precedence" {
    const path = "tests/feature_tests/basics/26_arithmetic_precedence";
    try expectSuccessfulBuild(path);
    try run(path);
}
