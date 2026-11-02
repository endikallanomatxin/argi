const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/226_ordinary_copy_name_does_not_change_ownership" {
    const path = "tests/feature_tests/contracts/226_ordinary_copy_name_does_not_change_ownership";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
