const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/34_print_terminator" {
    const path = "tests/feature_tests/io/34_print_terminator";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
