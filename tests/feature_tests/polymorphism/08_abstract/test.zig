const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/08_abstract" {
    const test_path = "tests/feature_tests/polymorphism/08_abstract";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
