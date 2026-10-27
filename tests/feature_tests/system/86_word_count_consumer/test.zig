const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/86_word_count_consumer" {
    try expectSuccessfulBuild("tests/feature_tests/system/86_word_count_consumer");
    try runExpect("tests/feature_tests/system/86_word_count_consumer", 0);
}
