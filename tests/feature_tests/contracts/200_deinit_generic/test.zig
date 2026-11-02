const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/200_deinit_generic" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/200_deinit_generic");
    try run("tests/feature_tests/contracts/200_deinit_generic");
}
