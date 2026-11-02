const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/84_unicode_scalar_literals" {
    try expectSuccessfulBuild("tests/feature_tests/text/84_unicode_scalar_literals");
    try run("tests/feature_tests/text/84_unicode_scalar_literals");
    try support.vmExpect("tests/feature_tests/text/84_unicode_scalar_literals", 0, null);
}
