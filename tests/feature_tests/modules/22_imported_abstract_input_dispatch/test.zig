const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/22_imported_abstract_input_dispatch" {
    const test_path = "tests/feature_tests/modules/22_imported_abstract_input_dispatch";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 45);
}
