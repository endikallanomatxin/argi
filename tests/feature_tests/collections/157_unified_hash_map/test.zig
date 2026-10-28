const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/157_unified_hash_map" {
    try expectSuccessfulBuild("tests/feature_tests/collections/157_unified_hash_map");
    try run("tests/feature_tests/collections/157_unified_hash_map");
    try support.vmExpect("tests/feature_tests/collections/157_unified_hash_map", 0, null);
}
