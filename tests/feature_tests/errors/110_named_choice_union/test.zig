const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/110_named_choice_union" {
    try expectSuccessfulBuild("tests/feature_tests/errors/110_named_choice_union");
    try runExpect("tests/feature_tests/errors/110_named_choice_union", 0);
}
