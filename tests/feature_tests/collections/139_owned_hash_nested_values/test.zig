const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/139_owned_hash_nested_values" {
    try expectSuccessfulBuild("tests/feature_tests/collections/139_owned_hash_nested_values");
    try runExpect("tests/feature_tests/collections/139_owned_hash_nested_values", 0);
}
