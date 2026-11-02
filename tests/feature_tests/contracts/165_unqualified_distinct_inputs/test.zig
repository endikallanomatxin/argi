const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/165_unqualified_distinct_inputs" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/165_unqualified_distinct_inputs");
    try support.runExpect("tests/feature_tests/contracts/165_unqualified_distinct_inputs", 0);
}
