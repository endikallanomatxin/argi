const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/136_comptime_lexical_boundaries" {
    try expectSuccessfulBuild("tests/feature_tests/execution/136_comptime_lexical_boundaries");
    try runExpect("tests/feature_tests/execution/136_comptime_lexical_boundaries", 42);
    try vmExpect("tests/feature_tests/execution/136_comptime_lexical_boundaries", 42, null);
}
