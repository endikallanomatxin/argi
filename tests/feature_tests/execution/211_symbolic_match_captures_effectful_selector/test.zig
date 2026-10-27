const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/211_symbolic_match_captures_effectful_selector" {
    try expectSuccessfulBuild("tests/feature_tests/execution/211_symbolic_match_captures_effectful_selector");
    try runExpect("tests/feature_tests/execution/211_symbolic_match_captures_effectful_selector", 42);
    try vmExpect("tests/feature_tests/execution/211_symbolic_match_captures_effectful_selector", 42, null);
}
