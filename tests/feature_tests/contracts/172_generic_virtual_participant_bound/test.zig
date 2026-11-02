const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/172_generic_virtual_participant_bound" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/172_generic_virtual_participant_bound");
    try run("tests/feature_tests/contracts/172_generic_virtual_participant_bound");
}
