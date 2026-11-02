const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/03_constants_and_variables" {
    const test_path = "tests/feature_tests/basics/03_constants_and_variables";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
