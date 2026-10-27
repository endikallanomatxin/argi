const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/69_utf8_text_boundary" {
    try expectSuccessfulBuild("tests/feature_tests/text/69_utf8_text_boundary");
    try run("tests/feature_tests/text/69_utf8_text_boundary");
}
