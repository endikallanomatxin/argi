const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/167_reached_contract_participant" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/167_reached_contract_participant");
    try support.runExpect("tests/feature_tests/contracts/167_reached_contract_participant", 0);
}
