const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/248_acquired_numeric_offset" {
    try expectSuccessfulBuild("tests/feature_tests/execution/248_acquired_numeric_offset");
    try runExpect("tests/feature_tests/execution/248_acquired_numeric_offset", 42);
    try vmExpect("tests/feature_tests/execution/248_acquired_numeric_offset", 42, null);
}
