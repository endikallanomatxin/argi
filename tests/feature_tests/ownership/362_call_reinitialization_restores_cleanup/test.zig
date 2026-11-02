const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/362_call_reinitialization_restores_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/362_call_reinitialization_restores_cleanup");
    try runExpect("tests/feature_tests/ownership/362_call_reinitialization_restores_cleanup", 42);
}
