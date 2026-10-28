const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/51_buffered_default_storage" {
    try expectSuccessfulBuild("tests/feature_tests/io/51_buffered_default_storage");
    try run("tests/feature_tests/io/51_buffered_default_storage");
}
