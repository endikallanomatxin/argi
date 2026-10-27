const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/264_fallible_indexed_replacement_preserves_owner" {
    try expectSuccessfulBuild("tests/feature_tests/execution/264_fallible_indexed_replacement_preserves_owner");
    try runExpect("tests/feature_tests/execution/264_fallible_indexed_replacement_preserves_owner", 42);
    try vmExpect("tests/feature_tests/execution/264_fallible_indexed_replacement_preserves_owner", 42, null);
}
