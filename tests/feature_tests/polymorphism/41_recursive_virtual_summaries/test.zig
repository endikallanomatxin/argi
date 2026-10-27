const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/41_recursive_virtual_summaries" {
    const path = "tests/feature_tests/polymorphism/41_recursive_virtual_summaries";
    try expectSuccessfulBuild(path);
    try run(path);
}
