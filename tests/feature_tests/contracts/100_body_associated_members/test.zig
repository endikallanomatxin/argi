const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/100_body_associated_members" {
    const path = "tests/feature_tests/contracts/100_body_associated_members";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
