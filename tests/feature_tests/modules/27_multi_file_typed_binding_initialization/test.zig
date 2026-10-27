const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/27_multi_file_typed_binding_initialization" {
    const test_path = "tests/feature_tests/modules/27_multi_file_typed_binding_initialization";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}
