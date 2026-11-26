const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/181_independent_forwarded_array_growth" {
    try expectSuccessfulBuild("tests/feature_tests/collections/181_independent_forwarded_array_growth");
    try runExpect("tests/feature_tests/collections/181_independent_forwarded_array_growth", 0);
}
