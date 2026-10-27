const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/81_utf8_copy_outlives_source" {
    try expectSuccessfulBuild("tests/feature_tests/text/81_utf8_copy_outlives_source");
    try run("tests/feature_tests/text/81_utf8_copy_outlives_source");
}
