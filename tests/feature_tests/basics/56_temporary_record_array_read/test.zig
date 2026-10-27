const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/56_temporary_record_array_read" {
    const path = "tests/feature_tests/basics/56_temporary_record_array_read";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
