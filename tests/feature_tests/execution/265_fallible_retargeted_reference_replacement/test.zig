const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/265_fallible_retargeted_reference_replacement" {
    try expectSuccessfulBuild("tests/feature_tests/execution/265_fallible_retargeted_reference_replacement");
    try runExpect("tests/feature_tests/execution/265_fallible_retargeted_reference_replacement", 42);
    try vmExpect("tests/feature_tests/execution/265_fallible_retargeted_reference_replacement", 42, null);
}
