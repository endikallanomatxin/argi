const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/290_known_default_participant_inference" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/290_known_default_participant_inference");
    try runExpect("tests/feature_tests/contracts/290_known_default_participant_inference", 0);
}
