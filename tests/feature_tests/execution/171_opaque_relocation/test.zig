const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/171_opaque_relocation" {
    try expectSuccessfulBuild("tests/feature_tests/execution/171_opaque_relocation");
    try runExpect("tests/feature_tests/execution/171_opaque_relocation", 42);
    try vmExpect("tests/feature_tests/execution/171_opaque_relocation", 42, null);
}
