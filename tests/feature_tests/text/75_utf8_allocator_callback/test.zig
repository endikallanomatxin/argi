const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/75_utf8_allocator_callback" {
    try expectSuccessfulBuild("tests/feature_tests/text/75_utf8_allocator_callback");
    try run("tests/feature_tests/text/75_utf8_allocator_callback");
}
