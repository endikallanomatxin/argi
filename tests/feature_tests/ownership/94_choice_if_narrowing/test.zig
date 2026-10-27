const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/94_choice_if_narrowing" {
    const test_path = "tests/feature_tests/ownership/94_choice_if_narrowing";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
