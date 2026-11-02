const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/275_opaque_wrapper_self_contained_owner" {
    const test_path = "tests/feature_tests/ownership/275_opaque_wrapper_self_contained_owner";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
