const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/135_projected_symbolic_read_before_consumption" {
    try expectSuccessfulBuild("tests/feature_tests/execution/135_projected_symbolic_read_before_consumption");
    try runExpect("tests/feature_tests/execution/135_projected_symbolic_read_before_consumption", 42);
    try vmExpect("tests/feature_tests/execution/135_projected_symbolic_read_before_consumption", 42, null);
}
