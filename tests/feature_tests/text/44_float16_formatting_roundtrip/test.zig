const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/44_float16_formatting_roundtrip" {
    const path = "tests/feature_tests/text/44_float16_formatting_roundtrip";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
