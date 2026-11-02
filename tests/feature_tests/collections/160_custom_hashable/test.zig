const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/160_custom_hashable" {
    try expectSuccessfulBuild("tests/feature_tests/collections/160_custom_hashable");
    try run("tests/feature_tests/collections/160_custom_hashable");
}
