const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/17_color_float_representation" {
    try expectSuccessfulBuild("tests/feature_tests/numbers/17_color_float_representation");
    try run("tests/feature_tests/numbers/17_color_float_representation");
}
