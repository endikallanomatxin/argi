const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/logging/01_writer_logger" {
    try expectSuccessfulBuild("tests/feature_tests/logging/01_writer_logger");
    try runExpect("tests/feature_tests/logging/01_writer_logger", 0);
}
