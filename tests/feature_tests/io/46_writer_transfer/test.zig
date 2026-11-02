const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/46_writer_transfer" {
    try expectSuccessfulBuild("tests/feature_tests/io/46_writer_transfer");
    try runExpect("tests/feature_tests/io/46_writer_transfer", 0);
}
