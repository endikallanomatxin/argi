const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/13_elementary_math" {
    try expectSuccessfulBuild("tests/feature_tests/numbers/13_elementary_math");
    try runExpect("tests/feature_tests/numbers/13_elementary_math", 0);
}
