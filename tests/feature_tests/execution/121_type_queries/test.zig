const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/121_type_queries" {
    try expectSuccessfulBuild("tests/feature_tests/execution/121_type_queries");
    try runExpect("tests/feature_tests/execution/121_type_queries", 42);
    try vmExpect("tests/feature_tests/execution/121_type_queries", 42, null);
}
