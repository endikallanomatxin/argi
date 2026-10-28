const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/81_temporary_directories" {
    try expectSuccessfulBuild("tests/feature_tests/system/81_temporary_directories");
    try runExpect("tests/feature_tests/system/81_temporary_directories", 0);
}
