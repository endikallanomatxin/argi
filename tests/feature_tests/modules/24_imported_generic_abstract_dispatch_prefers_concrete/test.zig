const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/24_imported_generic_abstract_dispatch_prefers_concrete" {
    const test_path = "tests/feature_tests/modules/24_imported_generic_abstract_dispatch_prefers_concrete";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 2);
}
