const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/14_participant_tuple" {
    const test_path = "tests/feature_tests/contracts/14_participant_tuple";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
