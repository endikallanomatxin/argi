const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/types/336_family_integer_parameter_alias" {
    const path = "tests/feature_tests/types/336_family_integer_parameter_alias";
    try expectSuccessfulBuild(path);
    try runExpect(path, 42);
    try vmExpect(path, 42, null);
}
