const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/27_imported_abstract_qualified_signature" {
    const test_path = "tests/feature_tests/modules/27_imported_abstract_qualified_signature";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
