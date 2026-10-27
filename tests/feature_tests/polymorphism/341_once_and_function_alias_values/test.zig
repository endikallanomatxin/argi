const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/polymorphism/341_once_and_function_alias_values" {
    const path = "tests/feature_tests/polymorphism/341_once_and_function_alias_values";
    try expectSuccessfulBuild(path);
    try runExpect(path, 42);
    try vmExpect(path, 42, null);
}
