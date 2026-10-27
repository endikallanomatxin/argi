const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/23_imported_abstract_monomorphization" {
    const test_path = "tests/feature_tests/modules/23_imported_abstract_monomorphization";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 3);
}
