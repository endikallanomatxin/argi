const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/139_reference_participant_specialization" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/139_reference_participant_specialization");
}
