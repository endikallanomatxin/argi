const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/pointers/09_addressable_struct_subfields" {
    const test_path = "tests/feature_tests/pointers/09_addressable_struct_subfields";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
