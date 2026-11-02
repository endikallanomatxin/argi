const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/229_virtual_mutation_preserves_stored_reference" {
    const test_path = "tests/feature_tests/ownership/229_virtual_mutation_preserves_stored_reference";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
