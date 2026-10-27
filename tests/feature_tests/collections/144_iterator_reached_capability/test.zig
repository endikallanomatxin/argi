const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/144_iterator_reached_capability" {
    try expectSuccessfulBuild("tests/feature_tests/collections/144_iterator_reached_capability");
    try run("tests/feature_tests/collections/144_iterator_reached_capability");
}
