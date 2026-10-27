const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/268_retargeted_replacement_preserves_other_references" {
    try expectSuccessfulBuild("tests/feature_tests/execution/268_retargeted_replacement_preserves_other_references");
    try runExpect("tests/feature_tests/execution/268_retargeted_replacement_preserves_other_references", 42);
    try vmExpect("tests/feature_tests/execution/268_retargeted_replacement_preserves_other_references", 42, null);
}
