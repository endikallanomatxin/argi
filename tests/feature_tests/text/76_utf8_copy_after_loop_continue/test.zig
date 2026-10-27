const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/76_utf8_copy_after_loop_continue" {
    try expectSuccessfulBuild("tests/feature_tests/text/76_utf8_copy_after_loop_continue");
    try run("tests/feature_tests/text/76_utf8_copy_after_loop_continue");
}
