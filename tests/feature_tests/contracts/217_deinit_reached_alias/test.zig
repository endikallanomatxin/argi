const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/217_deinit_reached_alias" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/217_deinit_reached_alias");
    try run("tests/feature_tests/contracts/217_deinit_reached_alias");
}
