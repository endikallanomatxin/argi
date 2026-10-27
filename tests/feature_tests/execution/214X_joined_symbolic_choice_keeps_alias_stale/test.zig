const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/214X_joined_symbolic_choice_keeps_alias_stale" {
    try buildExpectFail("tests/feature_tests/execution/214X_joined_symbolic_choice_keeps_alias_stale", "root that has ended");
    try vmExpect("tests/feature_tests/execution/214X_joined_symbolic_choice_keeps_alias_stale", 1, "root that has ended");
}
