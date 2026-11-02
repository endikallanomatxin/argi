const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/253_convert_borrowed_result" {
    const path = "tests/feature_tests/contracts/253_convert_borrowed_result";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
