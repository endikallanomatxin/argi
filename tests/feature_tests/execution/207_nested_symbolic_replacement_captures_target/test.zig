const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/207_nested_symbolic_replacement_captures_target" {
    try expectSuccessfulBuild("tests/feature_tests/execution/207_nested_symbolic_replacement_captures_target");
    try runExpect("tests/feature_tests/execution/207_nested_symbolic_replacement_captures_target", 42);
    try vmExpect("tests/feature_tests/execution/207_nested_symbolic_replacement_captures_target", 42, null);
}
