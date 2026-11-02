const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/369_symbolic_reference_reinitialization" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/369_symbolic_reference_reinitialization");
    try runExpect("tests/feature_tests/ownership/369_symbolic_reference_reinitialization", 42);
}
