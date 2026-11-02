const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/220_projected_replacement_through_args" {
    try expectSuccessfulBuild("tests/feature_tests/execution/220_projected_replacement_through_args");
    try runExpect("tests/feature_tests/execution/220_projected_replacement_through_args", 42);
    try vmExpect("tests/feature_tests/execution/220_projected_replacement_through_args", 42, null);
}
