const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/182_projected_write_after_array_growth" {
    try expectSuccessfulBuild("tests/feature_tests/collections/182_projected_write_after_array_growth");
    try runExpect("tests/feature_tests/collections/182_projected_write_after_array_growth", 0);
    try support.runExpectStdoutWithArgs("tests/feature_tests/collections/182_projected_write_after_array_growth", &.{ "one", "two" }, 0, "");
}
