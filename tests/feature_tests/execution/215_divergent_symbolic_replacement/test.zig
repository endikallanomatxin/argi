const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/215_divergent_symbolic_replacement" {
    try expectSuccessfulBuild("tests/feature_tests/execution/215_divergent_symbolic_replacement");
    try runExpect("tests/feature_tests/execution/215_divergent_symbolic_replacement", 42);
    try vmExpect("tests/feature_tests/execution/215_divergent_symbolic_replacement", 42, null);
}
