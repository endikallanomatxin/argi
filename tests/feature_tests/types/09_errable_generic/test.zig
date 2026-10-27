const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/09_errable_generic" {
    const test_path = "tests/feature_tests/types/09_errable_generic";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
