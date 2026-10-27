const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/145_opaque_mutation_external_pointer_allows_relocation" {
    const test_path = "tests/feature_tests/ownership/145_opaque_mutation_external_pointer_allows_relocation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
