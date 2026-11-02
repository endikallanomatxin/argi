const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/26_distinct_fields_do_not_alias_same_call" {
    const test_path = "tests/feature_tests/ownership/26_distinct_fields_do_not_alias_same_call";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 7);
}
