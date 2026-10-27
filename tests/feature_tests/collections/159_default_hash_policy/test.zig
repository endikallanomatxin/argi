const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/159_default_hash_policy" {
    try expectSuccessfulBuild("tests/feature_tests/collections/159_default_hash_policy");
    try run("tests/feature_tests/collections/159_default_hash_policy");
}
