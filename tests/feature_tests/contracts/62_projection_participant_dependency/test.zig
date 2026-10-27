const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/62_projection_participant_dependency" {
    const test_path = "tests/feature_tests/contracts/62_projection_participant_dependency";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
