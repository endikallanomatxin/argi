const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/02_defer" {
    const test_path = "tests/feature_tests/ownership/02_defer";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
