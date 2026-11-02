const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/373_symbolic_call_reinitialization" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/373_symbolic_call_reinitialization");
    try runExpect("tests/feature_tests/ownership/373_symbolic_call_reinitialization", 42);
}
