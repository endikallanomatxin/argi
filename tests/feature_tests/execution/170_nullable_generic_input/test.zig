const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/170_nullable_generic_input" {
    try expectSuccessfulBuild("tests/feature_tests/execution/170_nullable_generic_input");
    try runExpect("tests/feature_tests/execution/170_nullable_generic_input", 42);
    try vmExpect("tests/feature_tests/execution/170_nullable_generic_input", 42, null);
}
