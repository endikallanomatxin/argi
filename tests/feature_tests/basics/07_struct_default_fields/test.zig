const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/basics/07_struct_default_fields" {
    const test_path = "tests/feature_tests/basics/07_struct_default_fields";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
    try vmExpect("tests/feature_tests/basics/07_struct_default_fields", 0, null);
}
