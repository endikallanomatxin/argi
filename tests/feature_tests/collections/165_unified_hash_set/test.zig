const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/165_unified_hash_set" {
    try expectSuccessfulBuild("tests/feature_tests/collections/165_unified_hash_set");
    try runExpect("tests/feature_tests/collections/165_unified_hash_set", 0);
    try support.vmExpect("tests/feature_tests/collections/165_unified_hash_set", 0, null);
}
