const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/162_hashing_without_equality" {
    try expectSuccessfulBuild("tests/feature_tests/collections/162_hashing_without_equality");
    try run("tests/feature_tests/collections/162_hashing_without_equality");
}
