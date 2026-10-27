const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/execution/228X_zero_sized_establishment_bounds" {
    try expectSuccessfulBuild("tests/feature_tests/execution/228X_zero_sized_establishment_bounds");
    try runExpectFailure("tests/feature_tests/execution/228X_zero_sized_establishment_bounds");
    try vmExpect("tests/feature_tests/execution/228X_zero_sized_establishment_bounds", 1, "ExecutionAborted");
}
