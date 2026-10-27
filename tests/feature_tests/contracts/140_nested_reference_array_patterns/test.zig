const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/140_nested_reference_array_patterns" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/140_nested_reference_array_patterns");
    try runExpect("tests/feature_tests/contracts/140_nested_reference_array_patterns", 0);
}
