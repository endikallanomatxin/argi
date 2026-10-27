const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/145_owned_string_view_lookup" {
    try expectSuccessfulBuild("tests/feature_tests/collections/145_owned_string_view_lookup");
    try runExpect("tests/feature_tests/collections/145_owned_string_view_lookup", 0);
}
