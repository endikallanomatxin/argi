const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/06_anonymous_structs" {
    const test_path = "tests/feature_tests/basics/06_anonymous_structs";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
