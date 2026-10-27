const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/ownership/364_projected_call_reinitialization" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/364_projected_call_reinitialization");
    try runExpect("tests/feature_tests/ownership/364_projected_call_reinitialization", 42);
    try vmExpect("tests/feature_tests/ownership/364_projected_call_reinitialization", 42, null);
}
