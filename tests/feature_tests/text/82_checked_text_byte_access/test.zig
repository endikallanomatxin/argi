const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/82_checked_text_byte_access" {
    try expectSuccessfulBuild("tests/feature_tests/text/82_checked_text_byte_access");
    try run("tests/feature_tests/text/82_checked_text_byte_access");
}
