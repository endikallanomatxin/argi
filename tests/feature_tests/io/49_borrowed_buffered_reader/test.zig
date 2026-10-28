const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/49_borrowed_buffered_reader" {
    try expectSuccessfulBuild("tests/feature_tests/io/49_borrowed_buffered_reader");
    try run("tests/feature_tests/io/49_borrowed_buffered_reader");
}
