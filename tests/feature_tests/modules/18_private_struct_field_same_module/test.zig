const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/18_private_struct_field_same_module" {
    const test_path = "tests/feature_tests/modules/18_private_struct_field_same_module";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}
