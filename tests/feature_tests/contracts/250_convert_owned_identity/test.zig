const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/250_convert_owned_identity" {
    const path = "tests/feature_tests/contracts/250_convert_owned_identity";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
