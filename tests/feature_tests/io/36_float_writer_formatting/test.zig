const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/36_float_writer_formatting" {
    const path = "tests/feature_tests/io/36_float_writer_formatting";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
