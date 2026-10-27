const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/137_repeated_participant_specialization" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/137_repeated_participant_specialization");
}
