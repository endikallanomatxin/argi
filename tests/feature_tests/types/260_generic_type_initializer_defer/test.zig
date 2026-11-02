const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/260_generic_type_initializer_defer" {
    const test_path = "tests/feature_tests/types/260_generic_type_initializer_defer";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
