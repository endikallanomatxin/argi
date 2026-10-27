const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/219_generic_local_nominal_participant" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/219_generic_local_nominal_participant");
    try run("tests/feature_tests/contracts/219_generic_local_nominal_participant");
}
