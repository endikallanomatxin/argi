const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/78_utf8_bounded_line" {
    try expectSuccessfulBuild("tests/feature_tests/text/78_utf8_bounded_line");
    try run("tests/feature_tests/text/78_utf8_bounded_line");
}
