const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/types/324_type_family_arguments" {
    const path = "tests/feature_tests/types/324_type_family_arguments";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
    try vmExpect(path, 0, null);
}
