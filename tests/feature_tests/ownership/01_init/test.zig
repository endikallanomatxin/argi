const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/01_init" {
    const test_path = "tests/feature_tests/ownership/01_init";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
